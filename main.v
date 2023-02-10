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
}

struct Media {
	source string
	url    string
	width  int
	height int
}

fn get_extension(img string) string {
	return img#[-3..].to_lower()
}

fn check_size(config toml.Doc, width int, height int) bool {
	return width > config.value('min_width').int() && height > config.value('min_height').int()
		&& width > height
}

fn get_info_box(config toml.Doc, title string) bool {
	println('Looking infobox for ${title}')
	infobox := '${config.value('wiki_api_endpoint').string()}&prop=pageimages|pageterms&piprop=original&titles=${title}'
	res := http.get(infobox) or {
		panic('Failed to get data, error: ${err}')
		return false
	}

	data := json.decode(InfoBoxData, res.body) or {
		panic('Failed to parse json, error: ${err}')
		return false
	}

	media := data.query.pages[0].original
	extension := get_extension(media.source)

	if check_size(config, media.width, media.height) && (extension == 'jpg' || extension == 'png') {
		println('Downloading [${media.source}] image')
		http.download_file(media.source, './img/${title}.${extension}') or {
			panic('Failed to download image, error: ${err}')
			return false
		}

		return true
	} else {
		return false
	}
}

fn get_page(config toml.Doc, title string) bool {
	println('Looking for ${title}')
	page_info := '${config.value('wiki_api_endpoint').string()}&prop=imageinfo&generator=images&iiprop=url|size&titles=${title}'
	res := http.get(page_info) or {
		panic('Failed to get data, error: ${err}')
		return false
	}

	data := json.decode(InfoBoxData, res.body) or {
		panic('Failed to parse json, error: ${err}')
		return false
	}

	mut random_url := ''
	mut count := 0

	pages := data.query.pages.filter(it.imageinfo.len > 0
		&& (get_extension(it.imageinfo[0].url) == 'jpg'
		|| get_extension(it.imageinfo[0].url) == 'png'))

	if pages.len == 0 {
		return false
	}
	for {
		index := rand.intn(pages.len) or { 0 }
		media := pages[index].imageinfo[0]
		if check_size(config, media.width, media.height) {
			random_url = media.url
			break
		}
		count++
		if count > 200 {
			return false
		}
	}

	println('Downloading [${random_url}] image')
	http.download_file(random_url, './img/${title}.${get_extension(random_url)}') or {
		panic('Failed to download image, error: ${err}')
		return false
	}

	return true
}

fn main() {
	config := toml.parse_file('./config.toml') or { panic(err) }

	titles_json := os.read_file('./titles.json') or { '[]' }
	titles := json.decode([]string, titles_json) or {
		panic('Failed to parse json, error: ${err}')
		return
	}

	index := rand.intn(titles.len) or { 0 }
	title := titles[index]
	if !get_page(config, title) {
		get_info_box(config, title)
	}

	os.write_file('./.last_wiki_url', '${config.value('wiki_url').string()}${title}') or {
		panic('Failed to write file, error: ${err}')
		return
	}
}
