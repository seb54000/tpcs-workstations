const Hapi = require("hapi");
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

// create new server instance
//const apiServerName = process.env.HOSTNAME;
//console.log("Hostname" + apiServerName);
var server = new Hapi.Server({
  host: "0.0.0.0",
  port: 3000
});

//Connect to db
const mongoServerName = process.env.MONGOHOSTNAME;
console.log("Mongo Hostname = " + mongoServerName);
server.app.db = mongojs(mongoServerName + "/bibiotheque", ["books"]);

var apiPlugin = require("./routes/books.js");

// register plugins to server instance
init();
