package com.framelab.framelab

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.app.Activity
import android.content.ContentValues
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Path
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RectF
import android.graphics.Paint
import android.graphics.Rect
import android.media.ExifInterface
import android.media.MediaScannerConnection
import android.media.MediaMetadataRetriever
import android.os.Build
import android.os.Debug
import android.os.Environment
import android.os.StatFs
import android.provider.MediaStore
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.max
import kotlin.math.min

/** All byte-heavy work stays on one native worker; channel payloads are paths. */
class LocalMediaBridge(private val activity: Activity) {
    private val worker = Executors.newSingleThreadExecutor()
    private val segmenting = AtomicBoolean(false)
    private val cancelled = AtomicBoolean(false)
    private val runLock = Any()
    @Volatile private var activeRun: OrtSession.RunOptions? = null
    @Volatile private var closed = false

    fun handle(method: String, args: Map<String, Any?>, result: MethodChannel.Result) {
        if (method == "cancelBackgroundRemoval") {
            cancelInference()
            result.success(null)
            return
        }
        if (method == "availableBytes") { result.success(StatFs(activity.filesDir.path).availableBytes); return }
        if (method == "diagnostics") {
            val info = Debug.MemoryInfo()
            Debug.getMemoryInfo(info)
            result.success(mapOf("api" to Build.VERSION.SDK_INT, "model" to Build.MODEL,
                "pssKb" to info.totalPss, "freeBytes" to StatFs(activity.filesDir.path).availableBytes,
                "modelBundled" to true, "inferenceRuntime" to "ONNX Runtime 1.30.0"))
            return
        }
        if (method != "publish" && method != "removeBackground" && method != "getVideoThumbnail" && method != "processVideoCutoutFrames") { result.notImplemented(); return }
        if (closed) { result.error("CLOSED", "The media service is closed.", null); return }
        val segmentation = method == "removeBackground" || method == "processVideoCutoutFrames"
        if (segmentation && !segmenting.compareAndSet(false, true)) {
            result.error("BUSY", "Background removal is already running.", null); return
        }
        if (segmentation) cancelled.set(false)
        worker.execute {
            try {
                val path = args["path"] as? String ?: error("No media path supplied.")
                val file = if (method == "processVideoCutoutFrames") privateFrameDirectory(path) else privateFile(path)
                val output = when (method) {
                    "publish" -> publish(file, args["name"] as? String ?: "FrameLab.png", args["video"] == true)
                    "getVideoThumbnail" -> videoThumbnail(file, (args["timeSeconds"] as? Number)?.toDouble() ?: 0.0)
                    "processVideoCutoutFrames" -> processVideoCutoutFrames(file, args)
                    else -> removeBackground(file)
                }
                activity.runOnUiThread { result.success(output) }
            } catch (error: OutOfMemoryError) {
                activity.runOnUiThread { result.error("MEMORY", "This image exceeds available memory. Try a smaller image.", null) }
            } catch (error: Exception) {
                val message = if (cancelled.get() && segmentation) "Background removal cancelled." else (error.message ?: "Local media operation failed.")
                activity.runOnUiThread { result.error(if (cancelled.get() && segmentation) "CANCELLED" else "MEDIA", message, null) }
            } finally {
                if (segmentation) segmenting.set(false)
            }
        }
    }

    private fun privateFile(path: String): File {
        val file = File(path).canonicalFile
        val data = File(activity.applicationInfo.dataDir).canonicalPath + File.separator
        require(file.path.startsWith(data) && file.isFile) { "Media must be an imported local file." }
        return file
    }

    /** Android applies video rotation metadata before returning these frames.
     * Scaled retrieval avoids full-resolution bitmap allocation on API 27+.
     * Older devices serialize one bounded full-frame fallback at a time. */
    private fun videoThumbnail(source: File, seconds: Double): String {
        require(seconds.isFinite() && seconds >= 0.0) { "Choose a valid thumbnail time." }
        val roundedMs = ((seconds.coerceAtMost(43200.0) * 5).toLong() * 200)
        val signature = "${source.path}:${source.length()}:${source.lastModified()}:$roundedMs:v1"
        val digest = MessageDigest.getInstance("SHA-256").digest(signature.toByteArray(Charsets.UTF_8))
        val key = digest.joinToString("") { "%02x".format(it.toInt() and 255) }
        val folder = File(activity.cacheDir, "video_thumbnails")
        require(folder.exists() || folder.mkdirs()) { "Thumbnail cache could not be created." }
        val destination = File(folder, "$key.jpg")
        if (destination.isFile && destination.length() > 0) {
            destination.setLastModified(System.currentTimeMillis())
            return destination.path
        }
        val retriever = MediaMetadataRetriever()
        var frame: Bitmap? = null
        var scaled: Bitmap? = null
        val temporary = File(folder, "$key.tmp")
        try {
            retriever.setDataSource(source.path)
            val width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
            val height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
            require(width > 0 && height > 0 && width <= 16384 && height <= 16384) { "This clip has no supported video track." }
            if (Build.VERSION.SDK_INT < 27) {
                require(width.toLong() * height <= 12000000L) { "Preview thumbnails for this large clip require Android 8.1 or newer." }
            }
            val durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            val timeMs = if (durationMs > 0) roundedMs.coerceAtMost(max(0L, durationMs - 1)) else roundedMs
            val ratio = min(1.0, 160.0 / max(width, height))
            frame = if (Build.VERSION.SDK_INT >= 27) {
                retriever.getScaledFrameAtTime(timeMs * 1000, MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                    max(1, (width * ratio).toInt()), max(1, (height * ratio).toInt()))
            } else {
                retriever.getFrameAtTime(timeMs * 1000, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
            }
            val decoded = frame ?: error("This clip has no decodable preview frame.")
            val outputRatio = min(1.0, 160.0 / max(decoded.width, decoded.height))
            scaled = if (outputRatio < 1.0) Bitmap.createScaledBitmap(decoded,
                max(1, (decoded.width * outputRatio).toInt()), max(1, (decoded.height * outputRatio).toInt()), true) else decoded
            val thumbnail = scaled ?: error("Thumbnail scaling failed.")
            temporary.outputStream().use { require(thumbnail.compress(Bitmap.CompressFormat.JPEG, 82, it)) { "Thumbnail encoding failed." } }
            require(temporary.renameTo(destination)) { "Thumbnail cache write failed." }
            trimThumbnails(folder, destination)
            return destination.path
        } finally {
            if (scaled !== frame) scaled?.recycle()
            frame?.recycle()
            try { retriever.release() } catch (_: Exception) { }
            temporary.delete()
        }
    }

    private fun trimThumbnails(folder: File, newest: File) {
        val files = folder.listFiles { file -> file.extension == "jpg" }?.sortedBy { it.lastModified() } ?: return
        var count = files.size
        var bytes = files.sumOf { it.length() }
        for (file in files) {
            if (count <= 256 && bytes <= 24L * 1024 * 1024) break
            if (file == newest) continue
            val length = file.length()
            if (file.delete()) { count--; bytes -= length }
        }
    }

    private fun publish(source: File, suppliedName: String, video: Boolean): String {
        val name = suppliedName.replace(Regex("[^A-Za-z0-9._-]"), "_").take(100)
        require(name.isNotEmpty()) { "Choose an export name." }
        val mime = if (video) "video/mp4" else if (name.endsWith(".jpg") || name.endsWith(".jpeg")) "image/jpeg" else "image/png"
        require(StatFs(activity.filesDir.path).availableBytes > source.length() + 16L*1024*1024) { "Not enough storage to publish the export." }
        if (Build.VERSION.SDK_INT >= 29) {
            val collection = if (video) MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY) else MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(MediaStore.MediaColumns.MIME_TYPE, mime)
                put(MediaStore.MediaColumns.RELATIVE_PATH, (if (video) Environment.DIRECTORY_MOVIES else Environment.DIRECTORY_PICTURES) + "/FrameLab")
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val uri = activity.contentResolver.insert(collection, values) ?: error("Gallery entry could not be created.")
            try {
                activity.contentResolver.openOutputStream(uri)?.use { out -> source.inputStream().use { it.copyTo(out, 1024*1024) } } ?: error("Gallery output could not be opened.")
                activity.contentResolver.update(uri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
                return uri.toString()
            } catch (error: Exception) {
                activity.contentResolver.delete(uri, null, null)
                throw error
            }
        }
        @Suppress("DEPRECATION")
        val folder = File(Environment.getExternalStoragePublicDirectory(if (video) Environment.DIRECTORY_MOVIES else Environment.DIRECTORY_PICTURES), "FrameLab")
        require(folder.exists() || folder.mkdirs()) { "Gallery folder could not be created." }
        val destination = File(folder, "${System.currentTimeMillis()}_$name")
        try { source.copyTo(destination, overwrite = false) }
        catch (error: Exception) { destination.delete(); throw error }
        MediaScannerConnection.scanFile(activity, arrayOf(destination.path), arrayOf(mime), null)
        return destination.path
    }

    private fun decodeBounded(file: File, maxEdge: Int = 4096): Bitmap {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.path, bounds)
        require(bounds.outWidth > 0 && bounds.outHeight > 0) { "Unsupported or damaged image." }
        var sample = 1
        while (max(bounds.outWidth, bounds.outHeight) / sample > maxEdge) sample *= 2
        val bitmap = BitmapFactory.decodeFile(file.path, BitmapFactory.Options().apply { inSampleSize = sample; inPreferredConfig = Bitmap.Config.ARGB_8888; inMutable = true }) ?: error("Could not decode the image.")
        val orientation = try { ExifInterface(file.path).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL) } catch (_: Exception) { ExifInterface.ORIENTATION_NORMAL }
        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.setScale(-1f, 1f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.setRotate(180f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.setScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> { matrix.setRotate(90f); matrix.postScale(-1f, 1f) }
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.setRotate(90f)
            ExifInterface.ORIENTATION_TRANSVERSE -> { matrix.setRotate(-90f); matrix.postScale(-1f, 1f) }
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.setRotate(-90f)
        }
        if (matrix.isIdentity) return bitmap
        var oriented = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        if (oriented != bitmap) bitmap.recycle()
        if (!oriented.isMutable) {
            val mutable = oriented.copy(Bitmap.Config.ARGB_8888, true)
            oriented.recycle()
            oriented = mutable
        }
        return oriented
    }

    private fun <T> withSegmentationSession(action: (OrtSession) -> T): T {
        val model = File(activity.filesDir, "models/u2netp.onnx")
        if (!model.isFile || model.length() != 4574861L) {
            require(model.parentFile?.exists() == true || model.parentFile?.mkdirs() == true) {
                "The local model directory could not be created."
            }
            activity.assets.open("models/u2netp.onnx").use { stream ->
                model.outputStream().use { stream.copyTo(it) }
            }
        }
        val env = OrtEnvironment.getEnvironment()
        return OrtSession.SessionOptions().use { options ->
            options.setIntraOpNumThreads(2)
            options.setInterOpNumThreads(1)
            options.setOptimizationLevel(OrtSession.SessionOptions.OptLevel.ALL_OPT)
            env.createSession(model.path, options).use(action)
        }
    }

    /** Shared inference for a photo or a chunk of video frames. A chunk opens
     * one model session, then serially recycles each frame and mask. */
    private fun inferMask(original: Bitmap, session: OrtSession): Bitmap {
        var resized: Bitmap? = null
        try {
            if (cancelled.get()) error("Background removal cancelled.")
            resized = Bitmap.createScaledBitmap(original, 320, 320, true)
            val pixels = IntArray(320 * 320)
            resized.getPixels(pixels, 0, 320, 0, 0, 320, 320)
            var largest = 1f
            for (pixel in pixels) largest = max(largest,
                max(Color.red(pixel), max(Color.green(pixel), Color.blue(pixel))).toFloat())
            val input = ByteBuffer.allocateDirect(3 * 320 * 320 * 4)
                .order(ByteOrder.nativeOrder()).asFloatBuffer()
            val means = floatArrayOf(.485f, .456f, .406f)
            val stds = floatArrayOf(.229f, .224f, .225f)
            for (channel in 0..2) for (pixel in pixels) {
                val value = when (channel) {
                    0 -> Color.red(pixel); 1 -> Color.green(pixel); else -> Color.blue(pixel)
                }
                input.put((value / largest - means[channel]) / stds[channel])
            }
            input.rewind()
            val prediction = FloatArray(320 * 320)
            OnnxTensor.createTensor(OrtEnvironment.getEnvironment(), input,
                longArrayOf(1, 3, 320, 320)).use { tensor ->
                OrtSession.RunOptions().use { run ->
                    synchronized(runLock) {
                        if (cancelled.get()) error("Background removal cancelled.")
                        activeRun = run
                    }
                    try {
                        session.run(mapOf(session.inputNames.first() to tensor), run).use { results ->
                            (results[0] as OnnxTensor).floatBuffer.get(prediction)
                        }
                    } finally { synchronized(runLock) { activeRun = null } }
                }
            }
            if (cancelled.get()) error("Background removal cancelled.")
            val low = prediction.minOrNull() ?: 0f
            val high = prediction.maxOrNull() ?: 1f
            val range = max(high - low, .000001f)
            for (i in pixels.indices) {
                val alpha = (((prediction[i] - low) / range) * 255f).toInt().coerceIn(0, 255)
                pixels[i] = Color.argb(alpha, 255, 255, 255)
            }
            return Bitmap.createBitmap(pixels, 320, 320, Bitmap.Config.ARGB_8888)
        } finally { if (resized !== original) resized?.recycle() }
    }

    private fun applyMask(original: Bitmap, mask: Bitmap) {
        original.setHasAlpha(true)
        Canvas(original).drawBitmap(mask, null, Rect(0, 0, original.width, original.height),
            Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply {
                xfermode = PorterDuffXfermode(PorterDuff.Mode.DST_IN)
            })
    }

    private fun removeBackground(source: File): String {
        val original = decodeBounded(source)
        var mask: Bitmap? = null
        try {
            mask = withSegmentationSession { session -> inferMask(original, session) }
            applyMask(original, mask)
            val destination = File(source.parentFile, "cutout_${System.nanoTime()}.png")
            try {
                destination.outputStream().use {
                    require(original.compress(Bitmap.CompressFormat.PNG, 100, it)) { "PNG encoding failed." }
                }
            } catch (error: Exception) { destination.delete(); throw error }
            if (cancelled.get()) { destination.delete(); error("Background removal cancelled.") }
            return destination.path
        } finally { mask?.recycle(); original.recycle() }
    }

    private fun privateFrameDirectory(path: String): File {
        val folder = File(path).canonicalFile
        val roots = listOf(activity.filesDir.canonicalPath, activity.cacheDir.canonicalPath)
        require(folder.isDirectory && roots.any { folder.path.startsWith(it + File.separator) }) {
            "Video frames must be inside a private working directory."
        }
        return folder
    }

    private data class BrushStroke(val erase: Boolean, val radius: Float,
        val points: List<Pair<Float, Float>>)

    private fun parseBrushStrokes(value: Any?): List<BrushStroke> {
        if (value == null) return emptyList()
        val items = value as? List<*> ?: error("Invalid manual brushes.")
        require(items.size <= 200) { "Too many manual brush strokes." }
        return items.map { item ->
            val map = item as? Map<*, *> ?: error("Invalid manual brush.")
            val mode = map["mode"] as? String ?: error("A brush needs an erase or restore mode.")
            require(mode == "erase" || mode == "restore") { "Unknown brush mode." }
            val radius = (map["radius"] as? Number)?.toFloat() ?: error("A brush needs a radius.")
            require(radius.isFinite() && radius > 0 && radius <= 1f) { "Invalid brush radius." }
            val points = map["points"] as? List<*> ?: error("A brush needs points.")
            require(points.isNotEmpty() && points.size <= 4096) { "Invalid brush point count." }
            BrushStroke(mode == "erase", radius, points.map { point ->
                val pair = point as? Map<*, *> ?: error("Invalid brush point.")
                val x = (pair["x"] as? Number)?.toFloat() ?: error("Invalid brush x.")
                val y = (pair["y"] as? Number)?.toFloat() ?: error("Invalid brush y.")
                require(x.isFinite() && y.isFinite() && x in 0f..1f && y in 0f..1f) {
                    "Brush points must be normalized to the image."
                }
                x to y
            })
        }
    }

    private fun applyBrushes(cutout: Bitmap, original: Bitmap, strokes: List<BrushStroke>) {
        val canvas = Canvas(cutout)
        for (stroke in strokes) {
            val radius = stroke.radius * min(original.width, original.height)
            val points = stroke.points.map { it.first * original.width to it.second * original.height }
            if (stroke.erase) {
                val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    style = Paint.Style.STROKE; strokeWidth = radius * 2
                    strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND
                    xfermode = PorterDuffXfermode(PorterDuff.Mode.CLEAR)
                }
                if (points.size == 1) {
                    paint.style = Paint.Style.FILL
                    canvas.drawCircle(points[0].first, points[0].second, radius, paint)
                } else {
                    val path = Path().apply {
                        moveTo(points[0].first, points[0].second)
                        for (point in points.drop(1)) lineTo(point.first, point.second)
                    }
                    canvas.drawPath(path, paint)
                }
            } else {
                val region = Path()
                for (point in points) region.addCircle(point.first, point.second, radius, Path.Direction.CW)
                for (i in 1 until points.size) {
                    val a = points[i - 1]; val b = points[i]
                    val dx = b.first - a.first; val dy = b.second - a.second
                    val distance = kotlin.math.sqrt(dx * dx + dy * dy)
                    if (distance == 0f) continue
                    val nx = -dy * radius / distance; val ny = dx * radius / distance
                    // Same winding as circles: overlap remains filled.
                    region.moveTo(a.first - nx, a.second - ny)
                    region.lineTo(b.first - nx, b.second - ny)
                    region.lineTo(b.first + nx, b.second + ny)
                    region.lineTo(a.first + nx, a.second + ny)
                    region.close()
                }
                canvas.save()
                canvas.clipPath(region)
                canvas.drawBitmap(original, 0f, 0f, Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC)
                })
                canvas.restore()
            }
        }
    }

    private fun drawFilledBackground(canvas: Canvas, background: Bitmap, width: Int, height: Int) {
        val scale = max(width.toFloat() / background.width, height.toFloat() / background.height)
        val drawWidth = background.width * scale; val drawHeight = background.height * scale
        canvas.drawBitmap(background, null, RectF((width - drawWidth) / 2, (height - drawHeight) / 2,
            (width + drawWidth) / 2, (height + drawHeight) / 2),
            Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG))
    }

    /** A maximum of 30 frames bounds storage and memory. Dart extracts further
     * chunks and retains original audio while encoding the processed video.
     * Manual strokes are fixed image regions, reapplied to each frame; no
     * tracking or temporal quality guarantee is implied. */
    private fun processVideoCutoutFrames(folder: File, args: Map<String, Any?>): String {
        val frames = folder.listFiles { file -> file.isFile && file.extension.lowercase() == "png" }
            ?.sortedBy { it.name } ?: emptyList()
        require(frames.isNotEmpty() && frames.size <= 30) { "Process between 1 and 30 video frames per chunk." }
        val strokes = parseBrushStrokes(args["strokes"])
        val automatic = args["automatic"] != false
        val suppliedColor = (args["backgroundColor"] as? Number)?.toInt() ?: Color.BLACK
        val color = Color.rgb(Color.red(suppliedColor), Color.green(suppliedColor), Color.blue(suppliedColor))
        val backgroundPath = args["backgroundPath"] as? String
        var background: Bitmap? = null
        try {
            if (backgroundPath != null) background = decodeBounded(privateFile(backgroundPath), 1920)
            val processFrames: (OrtSession?) -> Unit = { session ->
                for (frame in frames) {
                    if (cancelled.get()) error("Background removal cancelled.")
                    val source = privateFile(frame.path)
                    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                    BitmapFactory.decodeFile(source.path, bounds)
                    require(bounds.outWidth in 1..1920 && bounds.outHeight in 1..1920) {
                        "Video cutout frames must have a maximum edge of 1920 pixels."
                    }
                    require(StatFs(folder.path).availableBytes >
                        bounds.outWidth.toLong() * bounds.outHeight * 8 + 16L * 1024 * 1024) {
                        "Not enough storage to refine the next video frame."
                    }
                    val original = decodeBounded(source, 1920)
                    var cutout: Bitmap? = null
                    var mask: Bitmap? = null
                    var output: Bitmap? = null
                    val temporary = File(folder, "${frame.name}.pending")
                    try {
                        cutout = original.copy(Bitmap.Config.ARGB_8888, true)
                        cutout.setHasAlpha(true)
                        if (automatic) {
                            mask = inferMask(original, requireNotNull(session))
                            applyMask(cutout, mask)
                        }
                        applyBrushes(cutout, original, strokes)
                        output = Bitmap.createBitmap(original.width, original.height, Bitmap.Config.ARGB_8888)
                        output.setHasAlpha(false)
                        val canvas = Canvas(output)
                        canvas.drawColor(color)
                        background?.let { drawFilledBackground(canvas, it, output.width, output.height) }
                        canvas.drawBitmap(cutout, 0f, 0f, Paint(Paint.ANTI_ALIAS_FLAG))
                        temporary.outputStream().use {
                            require(output.compress(Bitmap.CompressFormat.PNG, 100, it)) { "Frame encoding failed." }
                        }
                        if (cancelled.get()) error("Background removal cancelled.")
                        require(temporary.renameTo(frame)) { "Could not replace the refined video frame." }
                    } finally {
                        temporary.delete(); output?.recycle(); mask?.recycle()
                        cutout?.recycle(); original.recycle()
                    }
                }
            }
            if (automatic) withSegmentationSession { session -> processFrames(session) }
            else processFrames(null)
            return folder.path
        } finally { background?.recycle() }
    }

    fun close() {
        closed = true
        cancelInference()
        worker.shutdown()
    }

    private fun cancelInference() = synchronized(runLock) {
        cancelled.set(true)
        activeRun?.setTerminate(true)
        Unit
    }
}
