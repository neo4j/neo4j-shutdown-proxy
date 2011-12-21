
# $ requires npm install connect into
# require.paths [ '$HOME/.node_modules', '$HOME/.node_libraries', '/usr/lib/node' ]

fs = require 'fs'
connect = require 'connect'

process.on 'uncaughtException', (err) ->
    console.log "Type: " + err.type
    console.log "Message: " + err.message
    console.log "Arguments: " + err.arguments
    console.log err.stack

neo4jconfig = require "./neo4jconfig.coffee"
neo4jserver = require "./neo4jserver.coffee"
proxy = require "./proxy.coffee"

class ServerManager
    constructor: ->
        proxies = {}
        auth = { user: "admin", pass: "admin"}
        serverName = 'undefinded'

        bringUp = (id) ->
            config = neo4jconfig.parse id
            neo4j = neo4jserver.create config, serverName
            proxies[id] = proxy.buildFor neo4j, config

        storeConfig = ->
            config =
                auth : auth
                serverName : serverName
                proxies: (key for key of proxies)
            fs.writeFileSync "config.json", JSON.stringify(config)

        @loadConfig = ->
            try
                config = JSON.parse(fs.readFileSync "config.json")
                serverName = config['serverName']
                auth = config['auth']
                for instance in config['proxies']
                    try bringUp instance catch e
                        console.log "error during startup for "+ instance + " " + e
            catch error
                console.log error

        @start = ->
            connect(
                connect.basicAuth (user, pass) -> auth.user == user && auth.pass == pass
                connect.router (app) ->
                    app.get '/', (request, response) ->
                        res = {}
                        res[instance] = proxy.running() for instance, proxy of proxies
                        response.end JSON.stringify(res)

                    app.post '/:id', (request, response) ->
                        console.log "adding"
                        id = request.params.id
                        if (proxies[id]) then throw new Error "instance " + id + " is already registered"
                        bringUp id
                        storeConfig()
                        response.end "add "+request.params.id

                    app.delete '/:id', (request, response) ->
                        console.log "deleting"
                        id = request.params.id
                        if (!proxies[id]) then throw new Error "instance " + id + " is not registered"
                        proxies[id].stop()
                        delete proxies[id]
                        storeConfig()
                        response.end "delete "+request.params.id

            ).listen(7999)

serverManager = new ServerManager()
serverManager.loadConfig()
serverManager.start()

console.log "neo4j-cloud keeper started"
