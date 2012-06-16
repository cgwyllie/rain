
require 'lib/dmp'

module.exports = 
    uuid4: `function () {
        return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (c) {
                var r = Math.random()*16|0;
            var v = c == 'x' ? r : (r&0x3|0x8);
            return v.toString(16)
        })
    }`
    log: ->
        console.log(Array.prototype.slice.call(arguments)) if window.console?.log

    diffMatchPatch: new diff_match_patch()