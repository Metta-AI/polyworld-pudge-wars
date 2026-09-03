(function configurePolyworldWebInputs() {
  "use strict";

  if (typeof window === "undefined") {
    return;
  }

  var parameters = new URLSearchParams(window.location.search);
  var fragment = new URLSearchParams(window.location.hash.replace(/^#/, ""));
  if (!parameters.get("replay") && fragment.get("replay")) {
    parameters.set("replay", fragment.get("replay"));
  }
  var replayUrls = parameters.getAll("replay").filter(Boolean);
  var botSpecifications = parameters.getAll("bot").filter(Boolean);
  var existingArguments = Module["arguments"] || [];
  var alreadyReplay = existingArguments.indexOf("--replay") >= 0;
  var commandArguments = [];
  var inputs = [];

  if (replayUrls.length > 1) {
    throw new Error("Only one replay query parameter is allowed.");
  }

  function resolveUrl(source) {
    var url = new URL(source, window.location.href);
    if (url.protocol !== "http:" && url.protocol !== "https:") {
      throw new Error("Web inputs must use an HTTP or HTTPS URL: " + source);
    }
    return url.href;
  }

  function maybeGunzip(buf) {
    var bytes = new Uint8Array(buf);
    if (bytes.length >= 2 && bytes[0] === 0x1f && bytes[1] === 0x8b) {
      return new Response(
        new Blob([bytes]).stream().pipeThrough(
          new DecompressionStream("gzip")
        )
      ).arrayBuffer();
    }
    return Promise.resolve(buf);
  }

  function addInput(kind, source, name, suffix) {
    var path = "/web/" + name;
    inputs.push({
      kind: kind,
      source: source,
      url: resolveUrl(source),
      name: name
    });
    commandArguments.push("--" + kind, path + suffix);
  }

  if (replayUrls.length === 1 && !alreadyReplay) {
    addInput("replay", replayUrls[0], "replay.replay", "");
  }

  botSpecifications.forEach(function addBot(specification, index) {
    var match = specification.match(/^(.*):([0-9]+)$/);
    var source = match ? match[1] : specification;
    var suffix = match ? ":" + match[2] : "";
    addInput("bot", source, "bot" + index + ".bas", suffix);
  });

  [
    "seed",
    "seconds",
    "spawn-interval",
    "view",
    "ticks",
    "speed"
  ].forEach(function addValueParameter(name) {
    parameters.getAll(name).forEach(function addValue(value) {
      commandArguments.push("--" + name, value);
    });
  });

  if (parameters.has("verbose")) {
    commandArguments.push("--verbose");
  }

  if (parameters.has("join")) {
    // Networked follower mode. The lobby page passes join=1 meaning
    // "this same host"; an explicit ws:// or wss:// URL also works.
    var joinValue = parameters.get("join") || "";
    var joinUrl = joinValue.indexOf("ws") === 0
      ? joinValue
      : (window.location.protocol === "https:" ? "wss://" : "ws://") +
        window.location.host + "/ws";
    commandArguments.push("--join", joinUrl);
    ["name", "token", "slot", "netsim", "netsim-latency", "netsim-jitter",
     "netsim-loss"].forEach(function addJoinParameter(name) {
      var value = parameters.get(name);
      if (value === null || value === "") {
        return;
      }
      if (name === "slot") {
        // Seats from the API are 0-based (0..5). The client's "--slot="
        // form is 1-based and subtracts one, so map 0..5 -> 1..6. This is
        // the only form that can express seat 0: bare "--slot 0" is
        // rejected as "must be positive". The seat is authoritative from
        // the host's SlotGrant anyway, so this only satisfies validation.
        var seat = parseInt(value, 10);
        if (!isNaN(seat)) {
          commandArguments.push("--slot=" + (seat + 1));
        }
        return;
      }
      commandArguments.push("--" + name, value);
    });
  }

  Module["arguments"] = existingArguments.concat(commandArguments);
  if (inputs.length === 0) {
    return;
  }

  function showError(message) {
    console.error(message);
    if (typeof bootError === "function") {
      bootError(message);
      return;
    }
    var output = document.createElement("pre");
    output.textContent = message;
    output.style.background = "#220b0b";
    output.style.color = "#ffb4a9";
    output.style.font = "16px monospace";
    output.style.left = "24px";
    output.style.margin = "0";
    output.style.padding = "18px";
    output.style.position = "fixed";
    output.style.right = "24px";
    output.style.top = "24px";
    output.style.whiteSpace = "pre-wrap";
    output.style.zIndex = "1000";
    document.body.appendChild(output);
  }

  (Module["preRun"] || (Module["preRun"] = [])).push(
    function loadPolyworldWebInputs() {
      Module["FS_createPath"]("/", "web", true, true);
      inputs.forEach(function loadInput(input, index) {
        var dependency = "polyworld-web-input-" + index;
        Module["addRunDependency"](dependency);
        fetch(input.url, {credentials: "omit"})
          .then(function checkResponse(response) {
            if (!response.ok) {
              throw new Error(response.status + " " + response.statusText);
            }
            return response.arrayBuffer();
          })
          .then(maybeGunzip)
          .then(function installInput(buffer) {
            Module["FS_createDataFile"](
              "/web",
              input.name,
              new Uint8Array(buffer),
              true,
              false,
              true
            );
            Module["removeRunDependency"](dependency);
          })
          .catch(function reportInputError(error) {
            showError(
              "Failed to load " + input.kind + " from " + input.source +
              ".\n" + error.message
            );
          });
      });
    }
  );
})();
