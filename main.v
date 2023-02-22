import net.http
import json
import rand
import os
import toml
import gg

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
	config            toml.Doc
	title             string
	description       string
	wiki_url          string
	page_image_url    string
	infobox_image_url string
	width             int
	height            int
}

fn get_extension(img string) string {
	return img#[-3..].to_lower()
}

fn check_size(config toml.Doc, width int, height int) bool {
	min_size := width >= config.value('min_width').int()
		&& height >= config.value('min_height').int()
	conf_orientation := config.value_opt('orientation') or { toml.Any('both') }
	if conf_orientation.string() == 'horizontal' {
		return min_size && width > height
	}
	if conf_orientation.string() == 'vertical' {
		return min_size && height > width
	}

	return min_size
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

	pages := data.query.pages
	if pages.len == 0 {
		return false
	}

	index := rand.intn(pages.len) or { 0 }
	page := pages[index]
	if page.terms.description.len > 0 {
		app.description = page.terms.description[0]
	}

	media := page.original
	extension := get_extension(media.source)

	if check_size(app.config, media.width, media.height) && extension == 'jpg' {
		app.infobox_image_url = media.source
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

	pages := data.query.pages

	if pages.len == 0 {
		return false
	}
	for {
		index := rand.intn(pages.len) or { 0 }
		page := pages[index]
		if page.imageinfo.len == 0 {
			continue
		}
		img_info_index := rand.intn(page.imageinfo.len) or { 0 }
		media := page.imageinfo[img_info_index]
		if check_size(app.config, media.width, media.height) && get_extension(media.url) == 'jpg' {
			app.page_image_url = media.url
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

fn pick_non_empty(first string, second string) string {
	return if first != '' && second != '' {
		if rand.f32() < .5 {
			first
		} else {
			second
		}
	} else if first != '' {
		first
	} else {
		second
	}
}

fn main() {
	mut app := App{
		config: toml.parse_file('./config.toml') or { panic(err) }
		title: ''
		page_image_url: ''
		infobox_image_url: ''
	}

	titles_json := os.read_file('./titles.json') or { '[]' }
	titles := json.decode([]string, titles_json) or {
		panic('Failed to parse json, error: ${err}')
		return
	}

	mut download_image_url := ''
	for {
		index := rand.intn(titles.len) or { 0 }
		app.title = titles[index]
		app.get_info_box()
		app.get_page()

		download_image_url = pick_non_empty(app.page_image_url, app.infobox_image_url)

		if download_image_url != '' {
			break
		}
	}

	conf_out_path := app.config.value('out_file_path')
	mut out_path := ''
	if conf_out_path == toml.null {
		out_path = './img/${app.title}.${get_extension(download_image_url)}'
	} else {
		out_path = conf_out_path.string()
	}

	println('Downloading [${download_image_url}] image')
	http.download_file(download_image_url, out_path) or {
		panic('Failed to download image, error: ${err}')
		return
	}

	screen_size := gg.screen_size()
	wiki_url := '${app.config.value('wiki_url').string()}${app.title}'
	img_msg := '${app.title}\\n${app.description}\\nIturria: ${wiki_url}'
	if os.exists_in_system_path('magick') {
		println('Resizing image')
		new_size := '${screen_size.width}x${screen_size.height}'
		img_resize_cmd := 'magick convert -resize ${new_size}^ -gravity center -extent ${new_size} ${out_path} ${out_path}'
		os.execute(img_resize_cmd)

		println('Inserting data in image')
		pointsize := f32(screen_size.width) * 0.015
		annotate := '+20+${f32(screen_size.height) * 0.03}'
		img_data_cmd := 'magick convert -fill white -pointsize ${pointsize} -gravity SouthEast -annotate ${annotate} "${img_msg}" ${out_path} ${out_path}'
		os.execute(img_data_cmd)
	} else {
		os.write_file('./.last_wiki_url', img_msg) or {
			panic('Failed to write file, error: ${err}')
			return
		}
	}
}
