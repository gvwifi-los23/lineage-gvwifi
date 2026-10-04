package org.gvwifi.tweaks;

import android.app.Activity;
import android.content.ContentValues;
import android.content.ContentResolver;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.graphics.Insets;
import android.graphics.Typeface;
import android.net.Uri;
import android.os.Bundle;
import android.os.PowerExemptionManager;
import android.os.Process;
import android.provider.Settings;
import android.view.WindowInsets;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * gvwifi Tweaks: one screen for this ROM's optional setup. It applies the
 * tuning to installs whose settings predate it (new installs get it as
 * defaults), grants microG its permissions, and disables unused system apps.
 */
public class MainActivity extends Activity {

    private static final String MICROG = "com.google.android.gms";

    /** Unused system apps (same list as flash-kit/5-scripts/disabled-apps.txt). */
    private static final Map<String, String> UNUSED = new LinkedHashMap<>();
    static {
        UNUSED.put("com.android.messaging", "Messaging (SMS)");
        UNUSED.put("com.android.stk", "SIM Toolkit");
        UNUSED.put("com.android.simappdialog", "SIM app dialog");
        UNUSED.put("com.android.smspush", "SMS push");
        UNUSED.put("com.android.DeviceAsWebcam", "Device as webcam");
        UNUSED.put("com.android.dreams.basic", "Screen saver: basic");
        UNUSED.put("com.android.dreams.phototable", "Screen saver: photo table");
        UNUSED.put("com.android.egg", "Android Easter egg");
        UNUSED.put("com.android.healthconnect.controller", "Health Connect");
        UNUSED.put("com.android.bips", "Default print service");
        UNUSED.put("com.android.printservice.recommendation", "Print service recommendations");
        UNUSED.put("com.android.bluetoothmidiservice", "Bluetooth MIDI");
        UNUSED.put("com.android.hotspot2.osulogin", "Passpoint sign-in");
        UNUSED.put("com.android.dynsystem", "Dynamic System Updates");
        UNUSED.put("com.android.managedprovisioning", "Work profile setup");
        UNUSED.put("com.android.bookmarkprovider", "Bookmark provider");
        UNUSED.put("com.android.htmlviewer", "HTML viewer");
        UNUSED.put("org.lineageos.updater", "LineageOS Updater (no OTA server for this build)");
        UNUSED.put("org.lineageos.recorder", "Recorder");
        UNUSED.put("org.lineageos.etar", "Calendar (Etar)");
        UNUSED.put("org.lineageos.camelot", "PDF viewer (Camelot)");
        UNUSED.put("com.stevesoltys.seedvault", "Backup (Seedvault)");
        UNUSED.put("org.calyxos.backup.contacts", "Contacts backup");
        UNUSED.put("com.google.android.apps.googlecamera.fishfood", "Camera test app");
    }

    private CheckBox mTuning;
    private CheckBox mMicroG;
    private final List<CheckBox> mApps = new ArrayList<>();
    private TextView mResult;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        final int pad = (int) (16 * getResources().getDisplayMetrics().density);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(pad, pad, pad, pad);

        TextView title = new TextView(this);
        title.setText("gvwifi Tweaks");
        title.setTextSize(22);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        title.setPadding(0, 0, 0, pad / 2);
        root.addView(title);

        TextView intro = new TextView(this);
        intro.setText("Optional setup for this ROM. Nothing changes until you tap Apply.\n"
                + "Performance: already the default on new installs; apply it after upgrading.\n"
                + "microG: after installing microG, apply this to grant its permissions.");
        root.addView(intro);

        root.addView(header("Performance"));
        mTuning = check("0.5x animations, battery percentage", true);
        root.addView(mTuning);

        root.addView(header("microG"));
        mMicroG = check("Grant microG its permissions and battery exemption", installed(MICROG));
        mMicroG.setEnabled(installed(MICROG));
        if (!installed(MICROG)) mMicroG.setText(mMicroG.getText() + " (not installed)");
        root.addView(mMicroG);

        root.addView(header("Disable unused system apps (saves RAM; untick any you use)"));
        PackageManager pm = getPackageManager();
        for (Map.Entry<String, String> e : UNUSED.entrySet()) {
            if (!installed(e.getKey())) continue;
            boolean enabled = isEnabled(pm, e.getKey());
            CheckBox cb = check(e.getValue() + (enabled ? "" : "  (already disabled)"), enabled);
            cb.setTag(e.getKey());
            mApps.add(cb);
            root.addView(cb);
        }

        Button apply = new Button(this);
        apply.setText("Apply");
        apply.setOnClickListener(v -> apply());
        root.addView(apply);

        mResult = new TextView(this);
        root.addView(mResult);

        // Android 16 draws apps edge to edge: keep the content clear of the
        // status and navigation bars, or the top and bottom can't be reached.
        ScrollView scroll = new ScrollView(this);
        scroll.setClipToPadding(false);
        scroll.addView(root);
        scroll.setOnApplyWindowInsetsListener((v, insets) -> {
            Insets bars = insets.getInsets(
                    WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout());
            v.setPadding(bars.left, bars.top, bars.right, bars.bottom);
            return WindowInsets.CONSUMED;
        });
        setContentView(scroll);
    }

    private void apply() {
        StringBuilder out = new StringBuilder();
        ContentResolver cr = getContentResolver();

        // The panel only has a 60 Hz mode, so there is no refresh rate to set.
        if (mTuning.isChecked()) {
            try {
                Settings.Global.putFloat(cr, Settings.Global.WINDOW_ANIMATION_SCALE, 0.5f);
                Settings.Global.putFloat(cr, Settings.Global.TRANSITION_ANIMATION_SCALE, 0.5f);
                Settings.Global.putFloat(cr, Settings.Global.ANIMATOR_DURATION_SCALE, 0.5f);
                out.append("Animations set to 0.5x.\n");
            } catch (RuntimeException e) {
                out.append("Animations failed: ").append(e.getMessage()).append('\n');
            }
            try {
                ContentValues cv = new ContentValues();
                cv.put("name", "status_bar_show_battery_percent");
                cv.put("value", "2");
                cr.insert(Uri.parse("content://lineagesettings/system"), cv);
                out.append("Battery percentage shown.\n");
            } catch (RuntimeException e) {
                out.append("Battery percentage failed: ").append(e.getMessage()).append('\n');
            }
        }

        if (mMicroG.isChecked() && installed(MICROG)) {
            PackageManager pm = getPackageManager();
            int granted = 0;
            for (String p : new String[] {
                    "android.permission.ACCESS_FINE_LOCATION",
                    "android.permission.ACCESS_COARSE_LOCATION",
                    "android.permission.ACCESS_BACKGROUND_LOCATION",
                    "android.permission.READ_PHONE_STATE",
                    "android.permission.GET_ACCOUNTS",
                    "android.permission.POST_NOTIFICATIONS",
                    "android.permission.READ_CONTACTS" }) {
                try {
                    pm.grantRuntimePermission(MICROG, p, Process.myUserHandle());
                    granted++;
                } catch (RuntimeException ignored) {
                    // Permission not requested by this microG version.
                }
            }
            try {
                getSystemService(PowerExemptionManager.class).addToPermanentAllowList(MICROG);
                out.append("microG: ").append(granted).append(" permissions granted, battery exemption set.\n");
            } catch (RuntimeException e) {
                out.append("microG: ").append(granted).append(" permissions granted; battery exemption failed: ")
                        .append(e.getMessage()).append('\n');
            }
        }

        int disabled = 0, failed = 0;
        PackageManager pm = getPackageManager();
        for (CheckBox cb : mApps) {
            if (!cb.isChecked()) continue;
            String pkg = (String) cb.getTag();
            if (!isEnabled(pm, pkg)) continue;
            try {
                pm.setApplicationEnabledSetting(pkg,
                        PackageManager.COMPONENT_ENABLED_STATE_DISABLED_USER, 0);
                disabled++;
            } catch (RuntimeException e) {
                failed++;
            }
        }
        if (disabled + failed > 0) {
            out.append("Disabled ").append(disabled).append(" apps");
            if (failed > 0) out.append(" (").append(failed).append(" could not be disabled)");
            out.append(".\n");
        }
        mResult.setText(out.length() > 0 ? out.toString() : "Nothing selected.");
    }

    private TextView header(String text) {
        TextView t = new TextView(this);
        t.setText(text);
        t.setTypeface(Typeface.DEFAULT_BOLD);
        t.setPadding(0, (int) (16 * getResources().getDisplayMetrics().density), 0, 0);
        return t;
    }

    private CheckBox check(String text, boolean checked) {
        CheckBox cb = new CheckBox(this);
        cb.setText(text);
        cb.setChecked(checked);
        return cb;
    }

    private boolean installed(String pkg) {
        try {
            getPackageManager().getApplicationInfo(pkg, 0);
            return true;
        } catch (PackageManager.NameNotFoundException e) {
            return false;
        }
    }

    private static boolean isEnabled(PackageManager pm, String pkg) {
        try {
            int s = pm.getApplicationEnabledSetting(pkg);
            if (s == PackageManager.COMPONENT_ENABLED_STATE_DEFAULT) {
                ApplicationInfo ai = pm.getApplicationInfo(pkg, PackageManager.MATCH_DISABLED_COMPONENTS);
                return ai.enabled;
            }
            return s == PackageManager.COMPONENT_ENABLED_STATE_ENABLED;
        } catch (Exception e) {
            return false;
        }
    }
}
