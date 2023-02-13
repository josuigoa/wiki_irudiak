import net.http
import json
import rand
import os
import toml

struct InfoBoxData {
	query InfoBoxQuery
}

struct InfoBoxQuery {
	pages []InfoBoxPage
}

struct InfoBoxPage {
	pageid    int
	title     string
	original  Media
	imageinfo []Media
	terms     Terms
}

struct Media {
	source string
	url    string
	width  int
	height int
}

struct Terms {
	label       []string
	description []string
}

struct App {
mut:
	config      toml.Doc
	title       string
	description string
	wiki_url    string
	image_url   string
	width       int
	height      int
}

fn get_extension(img string) string {
	return img#[-3..].to_lower()
}

fn check_size(config toml.Doc, width int, height int) bool {
	return width > config.value('min_width').int() && height > config.value('min_height').int()
		&& width > height
}

fn (mut app App) get_info_box() bool {
	println('Looking infobox for ${app.title}')
	infobox := '${app.config.value('wiki_api_endpoint').string()}&prop=pageimages|pageterms&piprop=original&titles=${app.title}'
	res := http.get(infobox) or {
		panic('Failed to get data, error: ${err}')
		return false
	}

	data := json.decode(InfoBoxData, res.body) or {
		panic('Failed to parse json, error: ${err}')
		return false
	}

	if data.query.pages.len == 0 {
		return false
	}

	app.description = data.query.pages[0].terms.description[0]

	media := data.query.pages[0].original
	extension := get_extension(media.source)

	if check_size(app.config, media.width, media.height) && (extension == 'jpg') {
		app.image_url = media.source
		app.width = media.width
		app.height = media.height

		return true
	} else {
		return false
	}
}

fn (mut app App) get_page() bool {
	println('Looking for ${app.title}')
	page_info := '${app.config.value('wiki_api_endpoint').string()}&prop=imageinfo&generator=images&iiprop=url|size&titles=${app.title}'
	res := http.get(page_info) or {
		panic('Failed to get data, error: ${err}')
		return false
	}

	data := json.decode(InfoBoxData, res.body) or {
		panic('Failed to parse json, error: ${err}')
		return false
	}

	mut count := 0

	pages := data.query.pages.filter(it.imageinfo.len > 0
		&& get_extension(it.imageinfo[0].url) == 'jpg')

	if pages.len == 0 {
		return false
	}
	for {
		index := rand.intn(pages.len) or { 0 }
		media := pages[index].imageinfo[0]
		if check_size(app.config, media.width, media.height) {
			app.image_url = media.url
			app.width = media.width
			app.height = media.height

			break
		}
		count++
		if count > 200 {
			return false
		}
	}

	return true
}

fn main() {
	mut app := App{
		config: toml.parse_file('./config.toml') or { panic(err) }
		title: ''
		image_url: ''
	}

	titles_json := os.read_file('./titles.json') or { '[]' }
	titles := json.decode([]string, titles_json) or {
		panic('Failed to parse json, error: ${err}')
		return
	}

	for {
		index := rand.intn(titles.len) or { 0 }
		app.title = titles[index]
		if !app.get_info_box() {
			app.get_page()
		}
		if app.image_url != '' {
			break
		}
	}

	println('Downloading [${app.image_url}] image')
	http.download_file(app.image_url, './img/${app.title}.${get_extension(app.image_url)}') or {
		// http.download_file(app.image_url, app.config.value('out_file_path').string()) or {
		panic('Failed to download image, error: ${err}')
		return
	}

	wiki_url := '${app.config.value('wiki_url').string()}${app.title}'
	img_msg := '${app.title}\\n${app.description}\\nIturria: ${wiki_url}'
	if os.exists_in_system_path('magick') {
		println('Inserting data in image')
		pointsize := f32(app.width) * 0.015
		annotate := '+20+${f32(app.height) * 0.03}'
		img_magick_cmd := 'magick convert -fill white -pointsize ${pointsize} -gravity SouthEast -annotate ${annotate} "${img_msg}" ./img/${app.title}.jpg ./img/${app.title}.jpg'
		os.execute(img_magick_cmd)
	} else {
		os.write_file('./.last_wiki_url', img_msg) or {
			panic('Failed to write file, error: ${err}')
			return
		}
	}
}
