# Scheduling

Dimly can apply profiles automatically at set times - either at a fixed clock time or at sunrise/sunset based on your location.

---

## Enabling scheduling

1. Open **Settings → Schedule**.
2. Toggle **Enable Scheduling** on.
3. Click **Add Schedule** to create your first scheduled rule.

You can add as many schedules as you like and enable or disable individual ones without deleting them.

---

## Clock triggers

A **Clock** trigger fires at a fixed time each day (or on selected weekdays).

**To set up a clock schedule:**

1. Click **Add Schedule**.
2. Set the **Trigger type** to **Clock**.
3. Pick the time (hour and minute).
4. Choose the **Profile to apply**.
5. Set recurrence: **Every day**, or select specific weekdays.

Example: Apply your "Night" profile every weekday at 9 PM.

---

## Sunrise and Sunset triggers

A **Sunrise** or **Sunset** trigger fires relative to the solar event at your location. You can also add an offset (minutes before or after) to fine-tune the timing.

**To set up a solar schedule:**

1. Click **Add Schedule**.
2. Set the **Trigger type** to **Sunrise** or **Sunset**.
3. Set an offset if desired (e.g., −15 min to apply 15 minutes before sunset, or +10 min to apply 10 minutes after sunrise).
4. Choose the **Profile to apply**.
5. Set recurrence.

Sunrise and sunset times are calculated locally using your coordinates - no internet connection required after location is set.

---

## Setting your location

Solar triggers require your coordinates.

**Option 1: Use My Location**

Click **Use My Location** in Settings → Schedule → Location. Dimly will request your location from macOS. You'll see a standard macOS permission prompt - grant it to allow Dimly to read your location once.

**Option 2: Enter coordinates manually**

1. Find your coordinates in Apple Maps: right-click any location on the map → **Copy Coordinates**.
2. In Settings → Schedule → Location, expand **Or enter coordinates manually…**
3. Paste or type the latitude and longitude.
4. Click **Save Location**.

Your coordinates are stored locally and only used for sunrise/sunset calculations.

---

## Weekday selection

For any schedule, you can limit it to specific days of the week. Uncheck days you want to skip. Leave all days checked (or select **Every day**) for a daily schedule.

---

## How catch-up works

If your Mac was asleep or off when a schedule was supposed to fire, Dimly checks on wake whether a missed schedule falls within a 5-minute window. If it does, the profile is applied. This handles the common case of waking your Mac just after a scheduled time.

---

## Enabling and disabling individual schedules

Each schedule entry has an on/off toggle. Disable a schedule to pause it without losing its settings - useful for temporarily skipping a rule without having to recreate it later.

---

## Tips

- Pair scheduling with profiles: create a "Morning" profile (bright, all displays on) and a "Night" profile (dim, side displays off), then schedule them to apply automatically.
- Use a sunset trigger with a +30 min offset if you find natural sunset too early for your comfort.
- If you travel regularly, update your coordinates in the Location section to keep sunrise/sunset triggers accurate.
