import appdaemon.plugins.hass.hassapi as hass
from geopy.distance import geodesic
import math
from datetime import datetime, time
import pytz

class BrightnessByDistance(hass.Hass):

    def initialize(self):
        # Load parameters from apps.yaml
        self.home = (self.args["home_lat"], self.args["home_lon"])
        self.tracker = self.args["tracker"]
        self.light_entity = self.args["light_entity"]
        self.x0 = float(self.args.get("half_distance", 50))
        self.k = float(self.args.get("decay_rate", 0.1))
        self.time_zone = self.args.get("time_zone", "Europe/Oslo")
        self.enabled_toggle = self.args.get("enabled_toggle", None)

        self.local_tz = pytz.timezone(self.time_zone)

        # Schedule periodic updates
        # self.run_every(self.adjust_light, "now", 30)

        # Listen for state changes in the location tracker
        self.listen_state(self.adjust_light, self.tracker)

    def adjust_light(self, kwargs):
        # Check toggle if specified
        if self.enabled_toggle:
            toggle_state = self.get_state(self.enabled_toggle)
            if toggle_state != "on":
                self.log("Brightness control disabled via toggle.")
                return

        now = datetime.now(self.local_tz).time()

        # Only run during the allowed time window
        if not (time(7, 30) < now < time(23, 0)):
            self.log("Outside allowed time window, skipping brightness adjustment.")
            return

        lat = self.get_state(self.tracker, attribute="latitude")
        lon = self.get_state(self.tracker, attribute="longitude")

        if lat is None or lon is None or not isinstance(lat, float) or not isinstance(lon, float):
            self.log(f"Invalid coordinates for {self.tracker}. Latitude: {lat}, Longitude: {lon}")
            return

        distance = geodesic(self.home, (lat, lon)).meters
        sigmoid = 1 / (1 + math.exp(-self.k * (distance - self.x0)))
        brightness = int((1 - sigmoid) * 255)
        if distance <= 5:
            brightness = 255

        self.log(f"Latitude: {lat}, Longitude: {lon}, Distance: {distance:.2f} m -> Brightness: {brightness}")
        self.call_service("light/turn_on",
                  entity_id=self.light_entity,
                  brightness=brightness,
                  #rgb_color=[255, 0, 0],
                  color_temp_kelvin=800,
                  )
