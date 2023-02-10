import net.http
import json
import rand
import os

struct InfoBoxData {
pub:
	query InfoBoxQuery
}

struct InfoBoxQuery {
pub:
	pages []InfoBoxPage
}

struct InfoBoxPage {
pub:
	pageid    int
	title     string
	original  Media
	imageinfo []Media
}

struct Media {
pub:
	source string
	url    string
	width  int
	height int
}

const wiki_api_endpoint = 'https://eu.wikipedia.org/w/api.php?action=query&format=json&formatversion=2'

const min_width = 600

const min_height = 0

fn get_extension(img string) string {
	return img#[-3..].to_lower()
}

fn check_size(width int, height int) bool {
	return width > min_width && height > min_height && width > height
}

fn get_info_box(title string) bool {
	println('Looking infobox for ${title}')
	infobox := '${wiki_api_endpoint}&prop=pageimages|pageterms&piprop=original&titles=${title}'
	res := http.get(infobox) or {
		eprintln('Failed to get data, error: ${err}')
		return false
	}

	data := json.decode(InfoBoxData, res.body) or {
		eprintln('Failed to parse json, error: ${err}')
		return false
	}

	media := data.query.pages[0].original
	extension := get_extension(media.source)

	if check_size(media.width, media.height) && (extension == 'jpg' || extension == 'png') {
		println('Downloading [${media.source}] image')
		http.download_file(media.source, './img/${title}.${extension}') or {
			eprintln('Failed to download image, error: ${err}')
			return false
		}

		return true
	} else {
		return false
	}
}

fn get_page(title string) bool {
	println('Looking for ${title}')
	page_info := '${wiki_api_endpoint}&prop=imageinfo&generator=images&iiprop=url|size&titles=${title}'
	res := http.get(page_info) or {
		eprintln('Failed to get data, error: ${err}')
		return false
	}

	data := json.decode(InfoBoxData, res.body) or {
		eprintln('Failed to parse json, error: ${err}')
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
		if check_size(media.width, media.height) {
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
		eprintln('Failed to download image, error: ${err}')
		return false
	}

	return true
}

fn main() {
	titles_json := os.read_file('./titles.json') or { '[]' }
	titles := json.decode([]string, titles_json) or {
		eprintln('Failed to parse json, error: ${err}')
		return
	}

	index := rand.intn(titles.len) or { 0 }
	title := titles[index]
	if !get_page(title) {
		get_info_box(title)
	}

	/*
	os.write_file('./.title', title) or {
		eprintln('Failed to write file, error: ${err}')
		return
	}
	*/
}
