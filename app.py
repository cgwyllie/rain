
import tornado.ioloop
import tornado.web
import tornado.websocket
import tornado.gen
import tornado.escape as escape

import tornadoredis

REDIS_CHANNEL = 'events'

def newRedisClient():
	return tornadoredis.Client('localhost', 6379, None, None)

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
	
	@tornado.gen.engine
	def open(self):
		print "(rain) WS opened"
		snapshot = yield tornado.gen.Task(self.publisher.get, 'snapshot')
		patchList = yield tornado.gen.Task(self.publisher.lrange, 'patchList', 0, -1)
		if snapshot is not None:
			self.write_message(escape.json_encode({
				"event": 0,
				"snapshot": snapshot,
				"patchList": patchList,
				"user": ""
			}))
		
	@tornado.gen.engine
	def on_message(self, message):
		print "(rain) publish: " + message
		if message[0:1] == "s":
			print "(rain) Snapshotting..."
			message = message[1:]
			res = yield tornado.gen.Task(self.publisher.set, 'snapshot', message)
			print res
			res = yield tornado.gen.Task(self.publisher.delete, 'patchList')
			print res
		else:
			yield tornado.gen.Task(self.publisher.rpush, 'patchList', message)
		res = yield tornado.gen.Task(self.publisher.publish, REDIS_CHANNEL, message)
		print res

	def on_close(self):
		print "(rain) WS closed"
		self.client.unsubscribe(REDIS_CHANNEL)
		self.client.disconnect()

pubClient = newRedisClient()
pubClient.connect()

application = tornado.web.Application([
	(r"/websocket", EchoWSHandler),
	(r"/rain", RainHandler, dict(publisher=pubClient)),
	(r"/(.*)", tornado.web.StaticFileHandler, {"path": "./public"}),
])

if __name__ == "__main__":
	application.listen(8888)
	tornado.ioloop.IOLoop.instance().start()
