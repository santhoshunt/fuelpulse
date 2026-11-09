package com.fabletest.fuelpulse

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

// Home screen widgets. The app writes every value through home_widget's
// saveWidgetData (lib/services/home_widgets.dart) and asks each widget to
// redraw; these only copy the values into their layouts. A tap opens the
// app at a fuelpulse:// link the app's AppShell handles.

private fun open(context: Context, link: String) =
    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse(link))

/** Redraws every instance with [fill], which sets up one widget's views. */
private fun draw(
    context: Context,
    manager: AppWidgetManager,
    ids: IntArray,
    layout: Int,
    fill: RemoteViews.() -> Unit,
) {
    for (id in ids) {
        val views = RemoteViews(context.packageName, layout)
        views.fill()
        manager.updateAppWidget(id, views)
    }
}

private fun SharedPreferences.text(key: String, fallback: String = "") =
    getString(key, null) ?: fallback

class MileageWidget : HomeWidgetProvider() {
    override fun onUpdate(c: Context, m: AppWidgetManager, ids: IntArray, d: SharedPreferences) =
        draw(c, m, ids, R.layout.widget_mileage) {
            setTextViewText(R.id.cap, "MILEAGE · " + d.text("vehicle", "My H'ness"))
            setTextViewText(R.id.value, d.text("mileage_avg", "—"))
            setTextViewText(R.id.sub, d.text("mileage_sub", "Open My H'ness to update"))
            setOnClickPendingIntent(R.id.root, open(c, "fuelpulse://dashboard"))
        }
}

class QuickAddWidget : HomeWidgetProvider() {
    override fun onUpdate(c: Context, m: AppWidgetManager, ids: IntArray, d: SharedPreferences) =
        draw(c, m, ids, R.layout.widget_quick_add) {
            setTextViewText(R.id.cap, "QUICK ADD · " + d.text("vehicle", "My H'ness"))
            setOnClickPendingIntent(R.id.add, open(c, "fuelpulse://add"))
            setOnClickPendingIntent(R.id.scan, open(c, "fuelpulse://scan"))
        }
}

class TankWidget : HomeWidgetProvider() {
    override fun onUpdate(c: Context, m: AppWidgetManager, ids: IntArray, d: SharedPreferences) =
        draw(c, m, ids, R.layout.widget_tank) {
            setTextViewText(R.id.cap, "TANK · " + d.text("vehicle", "My H'ness"))
            setTextViewText(R.id.value, d.text("tank_value", "No tank size"))
            setTextViewText(R.id.sub, d.text("tank_sub"))
            setProgressBar(R.id.bar, 100, d.getInt("tank_percent", 0), false)
            setOnClickPendingIntent(R.id.root, open(c, "fuelpulse://dashboard"))
        }
}

class ServiceWidget : HomeWidgetProvider() {
    override fun onUpdate(c: Context, m: AppWidgetManager, ids: IntArray, d: SharedPreferences) =
        draw(c, m, ids, R.layout.widget_service) {
            setTextViewText(R.id.cap, "NEXT SERVICE · " + d.text("vehicle", "My H'ness"))
            setTextViewText(R.id.value, d.text("service_title", "Nothing scheduled"))
            setTextViewText(R.id.sub, d.text("service_left"))
            setProgressBar(R.id.bar, 100, d.getInt("service_percent", 0), false)
            setOnClickPendingIntent(R.id.root, open(c, "fuelpulse://service"))
        }
}

class SpendWidget : HomeWidgetProvider() {
    override fun onUpdate(c: Context, m: AppWidgetManager, ids: IntArray, d: SharedPreferences) =
        draw(c, m, ids, R.layout.widget_spend) {
            setTextViewText(R.id.cap, "FUEL SPEND · " + d.text("vehicle", "My H'ness"))
            setTextViewText(R.id.value, d.text("spend_month", "₹0 this month"))
            setTextViewText(R.id.sub, d.text("spend_avg"))
            d.getString("spend_chart", null)?.let { path ->
                BitmapFactory.decodeFile(path)?.let { setImageViewBitmap(R.id.chart, it) }
            }
            setOnClickPendingIntent(R.id.root, open(c, "fuelpulse://analytics"))
        }
}

class BestPumpWidget : HomeWidgetProvider() {
    override fun onUpdate(c: Context, m: AppWidgetManager, ids: IntArray, d: SharedPreferences) =
        draw(c, m, ids, R.layout.widget_best_pump) {
            setTextViewText(R.id.cap, "BEST PUMP · " + d.text("vehicle", "My H'ness"))
            setTextViewText(R.id.value, d.text("pump_title", "Not enough fill-ups yet"))
            setTextViewText(R.id.sub, d.text("pump_figures"))
            setOnClickPendingIntent(R.id.root, open(c, "fuelpulse://analytics"))
        }
}

class TripWidget : HomeWidgetProvider() {
    override fun onUpdate(c: Context, m: AppWidgetManager, ids: IntArray, d: SharedPreferences) =
        draw(c, m, ids, R.layout.widget_trip) {
            setTextViewText(R.id.cap, "TRIP · " + d.text("vehicle", "My H'ness"))
            setTextViewText(R.id.value, d.text("trip_title", "No trip on"))
            setTextViewText(R.id.sub, d.text("trip_sub"))
            setTextViewText(R.id.action, d.text("trip_action", "Start"))
            setOnClickPendingIntent(R.id.action, open(c, d.text("trip_link", "fuelpulse://starttrip")))
            setOnClickPendingIntent(R.id.root, open(c, d.text("trip_open", "fuelpulse://trips")))
        }
}

class OdometerWidget : HomeWidgetProvider() {
    override fun onUpdate(c: Context, m: AppWidgetManager, ids: IntArray, d: SharedPreferences) =
        draw(c, m, ids, R.layout.widget_odometer) {
            setTextViewText(R.id.cap, "ODOMETER · " + d.text("vehicle", "My H'ness"))
            setTextViewText(R.id.value, d.text("odo_value", "—"))
            setTextViewText(R.id.sub, d.text("odo_sub"))
            setOnClickPendingIntent(R.id.update, open(c, "fuelpulse://odometer"))
            setOnClickPendingIntent(R.id.photo, open(c, "fuelpulse://odometer?photo=1"))
            setOnClickPendingIntent(R.id.root, open(c, "fuelpulse://odometer"))
        }
}
