" File:          snipMate.vim
" Author:        Michael Sanders
" Version:       0.84
" Description:   snipMate.vim implements some of TextMate's snippets features in
"                Vim. A snippet is a piece of often-typed text that you can
"                insert into your document using a trigger word followed by a "<tab>".
"
"                For more help see snipMate.txt; you can do this by using:
"                :helptags ~/.vim/doc
"                :h snipMate.txt

if exists('loaded_snips') || &cp || version < 700
	finish
endif
let loaded_snips = 1
if !exists('snips_author') | let snips_author = 'Me' | endif

au BufRead,BufNewFile *.snippets\= set ft=snippet
au FileType snippet setl noet fdm=indent

let s:snippets = {} | let s:multi_snips = {}

if !exists('snippets_dir')
	let snippets_dir = substitute(globpath(&rtp, 'snippets/'), "\n", ',', 'g')
endif

fun! s:MakeSnip(scope, trigger, content)
	if !has_key(s:snippets, a:scope)
		let s:snippets[a:scope] = {}
	endif
	if !has_key(s:snippets[a:scope], a:trigger)
		let s:snippets[a:scope][a:trigger] = a:content
	else
		echom 'Warning in snipMate.vim: Snippet '.a:trigger.' is already defined.'
				\ .' See :h multi_snip for help on snippets with multiple matches.'
	endif
endf

fun! s:MakeMultiSnip(scope, trigger, content, desc)
	if !has_key(s:multi_snips, a:scope)
		let s:multi_snips[a:scope] = {}
	endif
	if !has_key(s:multi_snips[a:scope], a:trigger)
		let s:multi_snips[a:scope][a:trigger] = [[a:desc, a:content]]
	else
    let s:multi_snips[a:scope][a:trigger] += [[a:desc, a:content]]
	endif
endf

fun! ExtractSnipsFile(file, ft)
	if !filereadable(a:file) | return | endif
	let text = readfile(a:file)
	let inSnip = 0
	for line in text + ["\n"]
		if inSnip && (line[0] == "\t" || line == '')
			let content .= strpart(line, 1)."\n"
			continue
		elseif inSnip
			if empty(desc)
				call s:MakeSnip(a:ft, trigger, content[:-2])
			else
				call s:MakeMultiSnip(a:ft, trigger, content[:-2], desc)
			endif
			let inSnip = 0
		endif

		if line[:6] == 'snippet'
			let inSnip = 1
			let trigger = strpart(line, 8)
			let desc = ''
			let space = stridx(trigger, ' ') + 1
			if space " Process multi snip
				let desc = strpart(trigger, space)
				let trigger = strpart(trigger, 0, space - 1)
			endif
			let content = ''
		endif
	endfor
endf

" Reset snippets for filetype.
fun! ResetSnippets(ft)
	let ft = a:ft == '' ? '_' : a:ft
	for dict in [s:snippets, s:multi_snips, g:did_ft]
		if has_key(dict, ft)
			unlet dict[ft]
		endif
	endfor
endf

" Reset snippets for all filetypes.
fun! ResetAllSnippets()
	let s:snippets = {} | let s:multi_snips = {} | let g:did_ft = {}
endf

" Reload snippets for filetype.
fun! ReloadSnippets(ft)
	let ft = a:ft == '' ? '_' : a:ft
	call ResetSnippets(ft)
	call CreateSnippets(g:snippets_dir, ft)
endf

" Reload snippets for all filetypes.
fun! ReloadAllSnippets()
	for ft in keys(g:did_ft)
		call ReloadSnippets(ft)
	endfor
endf

let g:did_ft = {}
fun! CreateSnippets(dir, filetypes)
	for ft in split(a:filetypes, '\.')
		if has_key(g:did_ft, ft) | continue | endif
		call s:DefineSnips(a:dir, ft)
		let g:did_ft[ft] = 1
	endfor
endf

fun! s:DefineSnips(dir, filetype)
	let snippet_paths = split(globpath(a:dir, "*.snippets"), '\n')
	for path in snippet_paths
		let types = split(fnamemodify(path, ':t:r'), '\.')
		for type in types
			if type == a:filetype || type =~ "^" . a:filetype . "-.*"
				call ExtractSnipsFile(path, a:filetype)
				break
			endif
		endfor
	endfor
endf

fun! TriggerSnippet()
	if exists('g:SuperTabMappingForward')
		if g:SuperTabMappingForward == "<tab>"
			let SuperTabKey = "\<c-n>"
		elseif g:SuperTabMappingBackward == "<tab>"
			let SuperTabKey = "\<c-p>"
		endif
	endif

	if pumvisible() " Update snippet if completion is used, or deal with supertab
		if exists('SuperTabKey')
			call feedkeys(SuperTabKey) | return ''
		endif
		call feedkeys("\<esc>a", 'n') " Close completion menu
		call feedkeys("\<tab>") | return ''
	endif

	if exists('g:snipPos') | return snipMate#jumpNextTabStop() | endif

	let word = matchstr(getline('.'), '\S\+\%'.col('.').'c')
	for scope in [bufnr('%')] + split(&ft, '\.') + ['_']
		let [trigger, snippet] = s:GetSnippet(word, scope)
		" If word is a trigger for a snippet, delete the trigger & expand
		" the snippet.
		if snippet != ''
			let col = col('.') - len(trigger)
			sil exe 's/\V'.escape(trigger, '/\.').'\%#//'
			return snipMate#expandSnip(snippet, col)
		endif
	endfor

	if exists('SuperTabKey')
		call feedkeys(SuperTabKey)
		return ''
	endif
	return "\<tab>"
endf

fun! BackwardsSnippet()
	if exists('g:snipPos') | return snipMate#jumpPreviousTabStop() | endif

	if exists('g:SuperTabMappingForward')
		if g:SuperTabMappingBackward == "<s-tab>"
			let SuperTabKey = "\<c-p>"
		elseif g:SuperTabMappingForward == "<s-tab>"
			let SuperTabKey = "\<c-n>"
		endif
	endif
	if exists('SuperTabKey')
		call feedkeys(SuperTabKey)
		return ''
	endif
	return "\<s-tab>"
endf

fun! s:CreateSubstitutes(word)
	let words = []
	let word = a:word
	while !empty(word)
		call add(words, word)
		let word = substitute(word, '\(^\w\+\|^\W\+\)', '', '')
	endwhile
	return words
endf

fun! s:GetSnippet(word, scope)
	if !has_key(s:snippets, a:scope) && !has_key(s:multi_snips, a:scope)
		return ['', '']
	endif
	
	let snippets = get(s:snippets, a:scope, {})
	let multi_snips = get(s:multi_snips, a:scope, {})
	
	let words = s:CreateSubstitutes(a:word)
	if empty(words) | return ['', ''] | endif
	
	let word_and_snippet = []
	
	for word in words
		if has_key(snippets, escape(word, '\"'))
			let word_and_snippet = [word, snippets[word]]
			return word_and_snippet
		elseif has_key(multi_snips, escape(word, '\"'))
			let word_and_snippet = [word, s:ChooseMultiSnippet(a:scope, word)]
			return word_and_snippet
		endif
	endfor
	
	let last_word = words[-1]
	return [last_word, s:ChooseSnippet(a:scope, last_word)]
endf

fun! s:SelectList(lines)
	let i = inputlist(map(copy(a:lines), 'v:key + 1 . ". " . v:val')) - 1
	return 0 <= i && i < len(a:lines) ? i : -1
endf

fun! s:ChooseSnippet(scope, trigger)
	let escaped = escape(a:trigger, '\"')

	let triggers = []
	let snippets = []

	if has_key(s:snippets, a:scope)
		let single_triggers = filter(copy(s:snippets[a:scope]), 'v:key =~ "^' . escaped . '"')
		let triggers = keys(single_triggers)
		let snippets = values(single_triggers)
	endif

	if has_key(s:multi_snips, a:scope)
		let multi_triggers = filter(copy(s:multi_snips[a:scope]), 'v:key =~ "^' . escaped . '"')
		for [trigger, descs_and_snippets] in items(multi_triggers)
			for [desc, snippet] in descs_and_snippets
				call add(triggers, trigger . " " . desc)
				call add(snippets, snippet)
			endfor
		endfor
	endif

	if empty(triggers) | return '' | endif
	if len(triggers) == 1 | return snippets[0] | endif

	let i = s:SelectList(triggers)
	return i == -1 ? '' : snippets[i]
endf

fun! s:ChooseMultiSnippet(scope, trigger)
	let snippets = s:multi_snips[a:scope][a:trigger]

	if len(snippets) == 1 | return snippets[0][1] | endif

	let i = s:SelectList(map(copy(snippets), 'v:val[0]'))
	return i == -1 ? '' : snippets[i][1]
endf

fun! ShowAvailableSnips()
	let line  = getline('.')
	let col   = col('.')
	let word  = matchstr(getline('.'), '\S\+\%'.col.'c')
	let words = [word]
	if stridx(word, '.')
		let words += split(word, '\.', 1)
	endif
	let matchlen = 0
	let matches = []
	for scope in [bufnr('%')] + split(&ft, '\.') + ['_']
		let triggers = has_key(s:snippets, scope) ? keys(s:snippets[scope]) : []
		if has_key(s:multi_snips, scope) != -1
			let triggers += keys(s:multi_snips[scope])
		endif
		for trigger in triggers
			for word in words
				if word == ''
					let matches += [trigger] " Show all matches if word is empty
				elseif trigger =~ '^'.word
					let matches += [trigger]
					let len = len(word)
					if len > matchlen | let matchlen = len | endif
				endif
			endfor
		endfor
	endfor

	" This is to avoid a bug with Vim when using complete(col - matchlen, matches)
	" (Issue#46 on the Google Code snipMate issue tracker).
	call setline(line('.'), substitute(line, repeat('.', matchlen).'\%'.col.'c', '', ''))
	call complete(col, matches)
	return ''
endf
" vim:noet:sw=4:ts=4:ft=vim
