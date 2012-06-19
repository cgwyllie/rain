
import tornado.ioloop
import tornado.web
import tornado.websocket
import tornado.gen
import tornado.escape as escape

import tornadoredis

REDIS_CHANNEL = 'events'

EVENT_INIT = 0
EVENT_PUSH_PATCH = 1
EVENT_PUSH_SNAPSHOT = 2

def newRedisClient():
	return tornadoredis.Client('localhost', 6379, None, None)

"""
class EchoWSHandler(tornado.websocket.WebSocketHandler):
	def open(self):
		print "WS opened"
		self.pulseBeacon = tornado.ioloop.PeriodicCallback(self.pulse, 1000)
		self.pulseBeacon.start()

	def on_message(self, message):
		self.write_message(u"You said: " + message)

	def on_close(self):
		print "WS closed"
		self.pulseBeacon.stop()
		
	def pulse(self):
		self.write_message(u"pulse")
"""

class RainHandler(tornado.websocket.WebSocketHandler):
	def initialize(self, publisher):
		self.publisher = publisher
		self.listen()
	
	@tornado.gen.engine
	def listen(self):
		self.client = newRedisClient()
		self.client.connect()
		yield tornado.gen.Task(self.client.subscribe, REDIS_CHANNEL)
		self.client.listen(self.onEvent)
	
	def onEvent(self, message):
		print "(rain) Handler poked from Redis"
		if message.kind == 'message':
			self.write_message(str(message.body))
	
	def _getDocumentKey(self):
		return 'document:id'
	
	def _getDocumentPatchListKey(self):
		return 'document:id:patchList'

	@tornado.gen.engine
	def open(self):
		print "(rain) WS opened"
		document = yield tornado.gen.Task(self.publisher.hgetall, self._getDocumentKey())
		patchList = yield tornado.gen.Task(self.publisher.lrange, self._getDocumentPatchListKey(), 0, -1)
		print document
		print patchList
		title = ""
		snapshot = ""
		mode = ""
		
		if document:
			snapshot = document["snapshot"]
			title = document["title"]
			mode = document["mode"]

		self.write_message(escape.json_encode({
			"event": EVENT_INIT,
			"data": {
				"snapshot": snapshot,
				"title": title,
				"mode": mode,
				"patchList": patchList,
				"user": ""
			}
		}))
		
	@tornado.gen.engine
	def on_message(self, message):
		print "(rain) publish: " + message
		messageObject = escape.json_decode(message)
		
		if messageObject["event"] == EVENT_PUSH_SNAPSHOT:
			print "(rain) Snapshotting..."
			res = yield tornado.gen.Task(self.publisher.hmset, self._getDocumentKey(), {
						     'snapshot': messageObject["data"]["snapshot"],
						     'title': messageObject['data']['title'],
						     'mode': messageObject['data']['mode']})
			print res
			res = yield tornado.gen.Task(self.publisher.delete, self._getDocumentPatchListKey())
			print res
		else:
			res = yield tornado.gen.Task(self.publisher.rpush, self._getDocumentPatchListKey(), messageObject["data"]["patch"])
			print res
		res = yield tornado.gen.Task(self.publisher.publish, REDIS_CHANNEL, message)
		print res

	def on_close(self):
		print "(rain) WS closed"
		self.client.unsubscribe(REDIS_CHANNEL)
		self.client.disconnect()

pubClient = newRedisClient()
pubClient.connect()

application = tornado.web.Application([
	#(r"/websocket", EchoWSHandler),
	(r"/rain", RainHandler, dict(publisher=pubClient)),
	(r"/(.*)", tornado.web.StaticFileHandler, {"path": "./public"}),
])

if __name__ == "__main__":
	print "Rain starting up... Listening on localhost:8888"
	application.listen(8888)
	tornado.ioloop.IOLoop.instance().start()
