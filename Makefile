
default:
	handlebars app/templates -f app/templates.js -k each -k if
	stitchup -o public/assets/js/app.js -m DEVELOPMENT app
	lessc -x app/less/app.less > public/assets/css/app.css

run: default
	python app.py

clean:
	rm public/assets/css/app.css
	rm public/assets/js/app.js
	rm app/templates.js

clean-data:
	redis-cli KEYS "*" | xargs redis-cli DEL
