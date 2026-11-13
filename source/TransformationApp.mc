import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class TransformationApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        return [new TransformationView()];
    }

    // Called when the user changes settings in Garmin Connect / Connect IQ app
    function onSettingsChanged() as Void {
        WatchUi.requestUpdate();
    }
}
