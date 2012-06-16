
module.exports = 
    EventObserver: class EventObserver
        constructor: ->
            @callbacks = []
        
        on: (event, callback) ->
            (@callbacks[event] ?= []).push callback
            return this
        
        onAny: (events, callback) ->
            @on event, callback for event in events
        
        emit: ->
            args = Array.prototype.slice.call(arguments)
            event = args.shift()
            fn.apply(this, args) for fn in @callbacks[ event ] if @callbacks[ event ]?
    
    EventedWebSocket: class EventedWebSocket extends EventObserver
        connect: (url) ->
            @socket = new WebSocket(url)
            @socket.onopen = @onOpen
            @socket.onclose = @onClose
            @socket.onerror = @onError
            @socket.onmessage = @onMessage
        
        onOpen: (event) =>
            @emit 'socket.open', event
            
        onClose: (event) =>
            @emit 'socket.close', event
            
        onError: (event) =>
            @emit 'socket.error', event
        
        onMessage: (event) =>
            data = JSON.parse event.data
            @emit 'socket.onmessage', event, data.data
            @emit data['event'], data.data
    
        send: (event, message) ->
            @socket.send JSON.stringify({event: event, data: message})
