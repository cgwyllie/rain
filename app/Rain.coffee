
Util = require 'Util'
DMP = Util.diffMatchPatch
Events = require 'lib/Events'

Event =
    INIT: 0
    PUSH_PATCH: 1
    PUSH_SNAPSHOT: 2
    
EditorModes = [
    "markdown"
    "javascript"
    "php"
    "python"
    "ruby"
    "css"
    "xml"
    "mysql"
]
    
class Editor
    constructor: (@options) ->
        if not @options.codeMirrorArgs?
            @options.codeMirrorArgs =
                lineNumbers: true
                fixedGutter: true
                mode: 'markdown'
            
        @options.diffInterval = 800
        
        @codeMirror = CodeMirror.fromTextArea(
            @options.textArea,
            @options.codeMirrorArgs
        )
        
        @server = new Events.EventedWebSocket()
        @initServerHandler()
        @server.connect(@options.serverURL)
        
        @userId = Util.uuid4()
        
        @documentId = Util.uuid4()
        @documentTitle = ''
        @documentMode = 'markdown'
        
        @lastKnownValue = ""
        @diffInterval = null
        
        CodeMirror.commands.save = =>
            @save()

        CodeMirror.modeURL = "/assets/cm/mode/%N/%N.js" # TODO make configurable
        
        $('#modeSelect').change (e) =>
            @setMode e.target.value
            
        
        $('#documentTitle').keyup (e) =>
            @documentTitle = e.target.value
    
    setMode: (mode) ->
        return unless mode
        @documentMode = mode
        @codeMirror.setOption("mode", mode)
        CodeMirror.autoLoadMode(@codeMirror, mode)
        
        index = EditorModes.indexOf(@documentMode)
        index = 0 if index < 0
        $('#modeSelect')[0].selectedIndex = index
    
    save: ->
        @server.send(Event.PUSH_SNAPSHOT, {
            user: @userId
            snapshot: @codeMirror.getValue()
            title: @documentTitle
            mode: @documentMode
        })
    
    computeAndSendPatches: ->
        currentValue = @codeMirror.getValue()
        patches = DMP.patch_make(@lastKnownValue, currentValue)
        
        if patches.length
            @server.send(Event.PUSH_PATCH, {
                user: @userId
                patch: DMP.patch_toText(patches)
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
    
    setDocumentProperties: (properties) ->
        @documentTitle = properties.title
        $('#documentTitle').val(@documentTitle)
        
        @setMode properties.mode
    
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
            @setDocumentProperties(message)
            @lastKnownValue = message.snapshot
            for patch in message.patchList
                patched = DMP.patch_apply(
                    DMP.patch_fromText(patch),
                    @lastKnownValue
                )
                @lastKnownValue = patched[0]
            
            @codeMirror.setValue @lastKnownValue
        )
            
        @server.on Event.PUSH_SNAPSHOT, handlerWrap((message) =>
            @setDocumentProperties(message)
            @lastKnownValue = @codeMirror.getValue()
            patches = DMP.patch_make @lastKnownValue, message.snapshot # TODO: is this back to front? - No, want to update your state (if you're behind the times?!)
            patched = DMP.patch_apply patches, @lastKnownValue
            @setEditorValue patched[0]
        )
        
        @server.on Event.PUSH_PATCH, handlerWrap((message) =>
            @computeAndSendPatches()
            patched = DMP.patch_apply(
                DMP.patch_fromText(message.patch),
                @lastKnownValue
            )
            
            @setEditorValue patched[0]
        )

module.exports =
    Editor: Editor