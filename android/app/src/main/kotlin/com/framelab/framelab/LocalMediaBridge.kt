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
import android.graphics.Paint
import android.graphics.Rect
import android.media.ExifInterface
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Debug
import android.os.Environment
import android.os.StatFs
import android.provider.MediaStore
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
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
        if (method != "publish" && method != "removeBackground") { result.notImplemented(); return }
        if (closed) { result.error("CLOSED", "The media service is closed.", null); return }
        if (method == "removeBackground" && !segmenting.compareAndSet(false, true)) {
            result.error("BUSY", "Background removal is already running.", null); return
        }
        if (method == "removeBackground") cancelled.set(false)
        worker.execute {
            try {
                val path = args["path"] as? String ?: error("No media path supplied.")
                val file = privateFile(path)
                val output = if (method == "publish") publish(file, args["name"] as? String ?: "FrameLab.png", args["video"] == true)
                             else removeBackground(file)
                activity.runOnUiThread { result.success(output) }
            } catch (error: OutOfMemoryError) {
                activity.runOnUiThread { result.error("MEMORY", "This image exceeds available memory. Try a smaller image.", null) }
            } catch (error: Exception) {
                val message = if (cancelled.get() && method == "removeBackground") "Background removal cancelled." else (error.message ?: "Local media operation failed.")
                activity.runOnUiThread { result.error(if (cancelled.get() && method == "removeBackground") "CANCELLED" else "MEDIA", message, null) }
            } finally {
                if (method == "removeBackground") segmenting.set(false)
            }
        }
    }

    private fun privateFile(path: String): File {
        val file = File(path).canonicalFile
        val data = File(activity.applicationInfo.dataDir).canonicalPath + File.separator
        require(file.path.startsWith(data) && file.isFile) { "Media must be an imported local file." }
        return file
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

    private fun decodeBounded(file: File): Bitmap {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.path, bounds)
        require(bounds.outWidth > 0 && bounds.outHeight > 0) { "Unsupported or damaged image." }
        var sample = 1
        while (max(bounds.outWidth, bounds.outHeight) / sample > 4096) sample *= 2
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

    private fun removeBackground(source: File): String {
        val original = decodeBounded(source)
        var resized: Bitmap? = null
        var maskSmall: Bitmap? = null
        try {
            resized = Bitmap.createScaledBitmap(original, 320, 320, true)
            val pixels = IntArray(320*320)
            resized.getPixels(pixels,0,320,0,0,320,320)
            // Match U2Net/rembg normalization, including image-max normalization.
            var largest = 1f
            for (pixel in pixels) largest=max(largest,max(Color.red(pixel),max(Color.green(pixel),Color.blue(pixel))).toFloat())
            val input = ByteBuffer.allocateDirect(3*320*320*4).order(ByteOrder.nativeOrder()).asFloatBuffer()
            val means = floatArrayOf(.485f,.456f,.406f)
            val stds = floatArrayOf(.229f,.224f,.225f)
            for (channel in 0..2) for (pixel in pixels) {
                val value = when(channel) { 0 -> Color.red(pixel); 1 -> Color.green(pixel); else -> Color.blue(pixel) }
                input.put((value/largest-means[channel])/stds[channel])
            }
            input.rewind()
            val model = File(activity.filesDir,"models/u2netp.onnx")
            if (!model.isFile || model.length() != 4574861L) {
                model.parentFile?.mkdirs()
                activity.assets.open("models/u2netp.onnx").use { stream -> model.outputStream().use { stream.copyTo(it) } }
            }
            val env = OrtEnvironment.getEnvironment()
            val prediction = FloatArray(320*320)
            OrtSession.SessionOptions().use { options ->
                options.setIntraOpNumThreads(2)
                options.setInterOpNumThreads(1)
                options.setOptimizationLevel(OrtSession.SessionOptions.OptLevel.ALL_OPT)
                env.createSession(model.path,options).use { session ->
                    OnnxTensor.createTensor(env,input,longArrayOf(1,3,320,320)).use { tensor ->
                        OrtSession.RunOptions().use { run ->
                            synchronized(runLock) {
                                if (cancelled.get()) error("Background removal cancelled.")
                                activeRun = run
                            }
                            try {
                                session.run(mapOf(session.inputNames.first() to tensor),run).use { results ->
                                    (results[0] as OnnxTensor).floatBuffer.get(prediction)
                                }
                            } finally {
                                // The UI must never terminate already-closed RunOptions.
                                synchronized(runLock) { activeRun = null }
                            }
                        }
                    }
                }
            }
            if (cancelled.get()) error("Background removal cancelled.")
            val low = prediction.minOrNull() ?: 0f
            val high = prediction.maxOrNull() ?: 1f
            val range = max(high-low,0.000001f)
            for (i in pixels.indices) {
                val alpha = (((prediction[i]-low)/range)*255f).toInt().coerceIn(0,255)
                pixels[i] = Color.argb(alpha,255,255,255)
            }
            maskSmall = Bitmap.createBitmap(pixels,320,320,Bitmap.Config.ARGB_8888)
            // Scale the small mask while drawing directly into the mutable source.
            // This avoids two additional full-resolution ARGB bitmaps (128 MiB
            // for a 4096-square photo), while keeping the source file untouched.
            original.setHasAlpha(true)
            val canvas = Canvas(original)
            canvas.drawBitmap(maskSmall,null,Rect(0,0,original.width,original.height),Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply { xfermode=android.graphics.PorterDuffXfermode(android.graphics.PorterDuff.Mode.DST_IN) })
            // Keep the result beside its source asset so project deletion cleans it.
            val destination = File(source.parentFile,"cutout_${System.nanoTime()}.png")
            try { destination.outputStream().use { require(original.compress(Bitmap.CompressFormat.PNG,100,it)) } }
            catch (error: Exception) { destination.delete(); throw error }
            if (cancelled.get()) { destination.delete(); error("Background removal cancelled.") }
            return destination.path
        } finally {
            maskSmall?.recycle()
            if (resized != original) resized?.recycle()
            original.recycle()
        }
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
