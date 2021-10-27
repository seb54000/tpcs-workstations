const Hapi = require("@hapi/hapi");
const mongojs = require("mongojs");

async function init() {
  await server.register(apiPlugin);
  console.log("Plugin registered");
  server.start(function(err) {
    if (err) {
      console.log("An error occured on start");
      throw err;
    }
  });
  console.log("Server running at: " + server.info.uri);
}

var server = new Hapi.Server({
  host: "0.0.0.0",
  port: 3000
});

//Connect to db
var mongoServerName = "bibliomongo";
console.log("Mongo Hostname = " + mongoServerName);
server.app.db = mongojs(mongoServerName + "/bibiotheque", ["books"]);

var apiPlugin = require("./routes/books.js");

// register plugins to server instance
init();
