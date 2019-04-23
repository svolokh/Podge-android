package io.podge.podge;

import android.app.*;
import org.libsdl.app.SDLActivity;

public class PodgeActivity extends SDLActivity {
    @Override
    protected String[] getLibraries() {
        return new String[] {
            "podge"
        };
    }
}
