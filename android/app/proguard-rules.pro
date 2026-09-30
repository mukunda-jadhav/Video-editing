# Native runtimes register Java classes/methods through JNI by name.
# Keep those boundaries intact in minified release builds.
-keep class com.antonkarpenko.ffmpegkit.** { *; }
-keep class ai.onnxruntime.** { *; }
