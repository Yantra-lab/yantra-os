// Yantra for Android — the Java half.
//
// What it does, and nothing else:
//   1. copies the APK's `assets/apps/**` to the app's private storage ONCE (a
//      byte copy; the modules are the desktop's, unchanged — see
//      docs/ANDROID.md §interchangeability), so the engine can open them by path;
//   2. tells the SDL thread which app to boot (`YANTRA_APP`, default "desktop");
//   3. hands the process to SDL's own SDLActivity, which loads libSDL3.so and
//      then libmain.so and calls SDL_main on the SDL thread.
//
// Everything that draws, runs WebAssembly or handles input is native
// (libmain.so = android/src/yantra_android.nim + the shared engine). No UI is
// built here, and no app logic lives in Java.
package com.svarogsystems.yantra;

import android.os.Bundle;
import android.util.Log;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.IOException;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

import org.libsdl.app.SDLActivity;

public class MainActivity extends SDLActivity {
    private static final String TAG = "YantraHost";
    /** Bump when the asset layout changes, to force a re-copy on upgrade. */
    private static final String ASSET_STAMP = "apps-v1";

    @Override
    protected String[] getLibraries() {
        // SDL3 first: libSDL3.so exports JNI_OnLoad, libmain.so needs it.
        return new String[] { "SDL3", "main" };
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        try {
            File apps = new File(getFilesDir(), "apps");
            File stamp = new File(getFilesDir(), ASSET_STAMP);
            if (!stamp.exists() || !apps.isDirectory()) {
                int n = copyAssetTree("apps", apps);
                stamp.delete();
                stamp.createNewFile();
                Log.i(TAG, "assets copied: " + n + " files -> " + apps.getAbsolutePath());
            } else {
                Log.i(TAG, "assets already installed at " + apps.getAbsolutePath());
            }
            nativeSetenv("YANTRA_DATA_DIR", getFilesDir().getAbsolutePath());
            String app = null;
            if (getIntent() != null) app = getIntent().getStringExtra("app");
            if (app != null && app.length() > 0) {
                nativeSetenv("YANTRA_APP", app);
                Log.i(TAG, "requested app: " + app);
            }
        } catch (Throwable t) {
            Log.e(TAG, "asset install failed: " + t.toString());
        }
        super.onCreate(savedInstanceState);
    }

    /** Recursively copies `assets/<src>` into `dst`; returns the file count. */
    private int copyAssetTree(String src, File dst) throws IOException {
        int count = 0;
        String[] entries = getAssets().list(src);
        if (entries != null && entries.length > 0) {
            if (!dst.exists() && !dst.mkdirs()) throw new IOException("mkdirs " + dst);
            for (String e : entries) count += copyAssetTree(src + "/" + e, new File(dst, e));
            return count;
        }
        // a file, not a directory
        InputStream in = getAssets().open(src);
        try {
            OutputStream out = new FileOutputStream(dst);
            try {
                byte[] buf = new byte[64 * 1024];
                int r;
                while ((r = in.read(buf)) > 0) out.write(buf, 0, r);
            } finally {
                out.close();
            }
        } finally {
            in.close();
        }
        return 1;
    }
}
