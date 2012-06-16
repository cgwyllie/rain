
Util = require 'Util'
DMP = Util.diffMatchPatch
Events = require 'lib/Events'

Event =
    INIT: 0
    PUSH_PATCH: 1
    PUSH_SNAPSHOT: 2
    
class Editor
    constructor: (@options) ->
        if not @options.codeMirrorArgs?
            @options.codeMirrorArgs =
                lineNumbers: true
                fixedGutter: true
            
        @options.diffInterval = 800
        
        @codeMirror = CodeMirror.fromTextArea(
            @options.textArea,
            @options.codeMirrorArgs
        )
        
        @server = new Events.EventedWebSocket()
        @initServerHandler()
        @server.connect(@options.serverURL)
        
        @userId = Util.uuid4()
        
        @lastKnownValue = ""
        @diffInterval = null
        
        CodeMirror.commands.save = =>
            @save()

        CodeMirror.modeURL = "/assets/cm/mode/%N/%N.js" # TODO make configurable
        
        $('#modeSelect').change (e) ->
            @codeMirror.setOption("mode", e.target.value)
            CodeMirror.autoLoadMode(@codeMirror, e.target.value)
        
    save: ->
        @server.send(Event.PUSH_SNAPSHOT, {
            user: @userId
            data: @codeMirror.getValue()
        })
    
    computeAndSendPatches: ->
        currentValue = @codeMirror.getValue()
        patches = DMP.patch_make(@lastKnownValue, currentValue)
        
        if patches.length
            @server.send(Event.PUSH_PATCH, {
                user: @userId
                data: DMP.patch_toText(patches)
            })
        
        @lastKnownValue = currentValue
        
    setEditorValue: (newValue) ->
        currentCursor = @codeMirror.getCursor()
        
        lineCount = @codeMirror.lineCount()
        @codeMirror.setValue(newValue)
        newLineCount = @codeMirror.lineCount()
        
        # TODO: Update for same line editing too based on line lengths?
        if newLineCount < lineCount
            currentCursor.line -= (lineCount - newLineCount)
        else if newLineCount > lineCount
            currentCursor.line += (newLineCount - lineCount)
        
        @codeMirror.setCursor(currentCursor)
        @lastKnownValue = newValue
        
    diffFn: =>
        @computeAndSendPatches()
    
    startDiffing: ->
        @diffInterval = setInterval(@diffFn, @options.diffInterval) unless @diffInterval?
    
    stopDiffing: ->
        if @diffInterval?
            clearInterval(@diffInterval)
            @diffInterval = null
        
    handle: (message, fn) ->
        if message.user != @userId
            fn(message)
        
    initServerHandler: ->
        handlerWrap = (fn) =>
            return ((message) =>
                if message.user != @userId
                    @stopDiffing()
                    fn(message)
                    @startDiffing()
            )

        @server.on Event.INIT, handlerWrap((message) =>
            @lastKnownValue = message.snapshot
            for patch in message.patchList
                patch = JSON.parse patch
                patched = DMP.patch_apply(
                    DMP.patch_fromText(patch.data.data),
                    @lastKnownValue
                )
                @lastKnownValue = patched[0]
            
            @codeMirror.setValue @lastKnownValue
        )
            
        @server.on Event.PUSH_SNAPSHOT, handlerWrap((message) =>
            @lastKnownValue = @codeMirror.getValue()
            patches = DMP.patch_make @lastKnownValue, message.data # TODO: is this back to front? - No, want to update your state (if you're behind the times?!)
            patched = DMP.patch_apply patches, @lastKnownValue
            @setEditorValue patched[0]
        )
        
        @server.on Event.PUSH_PATCH, handlerWrap((message) =>
            @computeAndSendPatches()
            patched = DMP.patch_apply(
                DMP.patch_fromText(message.data),
                @lastKnownValue
            )
            
            @setEditorValue patched[0]
        )

module.exports =
    Editor: Editor