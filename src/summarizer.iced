tablify        = require 'tablify'
path           = require 'path'
fs             = require 'fs'
{make_esc}     = require 'iced-error'
{PackageJson}  = require './package'
constants      = require './constants'
{item_types}   = require './constants'
utils          = require './utils'
GitPreset      = require './preset/git'
DropboxPreset  = require './preset/dropbox'
GlobberPreset  = require './preset/globber'
XPlatformHash  = require './x_platform_hash'

# =====================================================================================================================

class SummarizedItem

  constructor: ({parent_path, fname, summarizer, depth})  ->
    @parent_path      = parent_path
    @fname            = fname
    @summarizer       = summarizer
    @depth            = depth or 0
    @item_type        = null
    @realpath         = null
    @link             = null
    @contents         = null
    @hash             = null
    @stats            = null # slightly different for symbolic links

  # -------------------------------------------------------------------------------------------------------------------

  load_traverse: (cb) ->
    esc = make_esc cb, "SummarizedItem::load"
    p   = path.join @summarizer.root_dir(), @parent_path, @fname
    await  fs.realpath p, esc defer @realpath
    await  fs.lstat    p, esc defer @stats
    if @stats?.isSymbolicLink()
      @item_type = item_types.SYMLINK
      await fs.readlink p, esc defer @link
    else if @stats.isFile()
      @item_type = item_types.FILE
      await @hash_contents esc defer @hash
    else
      @contents  = []
      @item_type = item_types.DIR
      await fs.readdir @realpath, esc defer fnames
      for f in fnames when f isnt '.'
        subpath = path.join @realpath, f
        await @summarizer.should_ignore subpath, esc defer ignore
        if not ignore
          si = @subitem f
          await si.load_traverse esc defer()
          @contents.push si
        else
          console.log "Ignoring #{subpath}..."
      @contents.sort (a,b) -> a.fname.localeCompare(b.fname, 'us')
    cb()

  # -------------------------------------------------------------------------------------------------------------------

  subitem: (f) ->
    new SummarizedItem {
      fname:        f, 
      parent_path:  if @parent_path.length then "#{@parent_path}/#{@fname}" else @fname 
      summarizer:   @summarizer
      depth:        @depth + 1
    }

  # -------------------------------------------------------------------------------------------------------------------

  signable_info: ->
    info =
      depth:         @depth
      parent_path:   @parent_path
      item_type:     @item_type
      fname:         @fname
      path:          if @parent_path.length then "#{@parent_path}/#{@fname}" else @fname
      exec:          utils.is_user_executable @stats

    switch @item_type
      when item_types.FILE
        info.hash = @hash
        info.size = @stats.size
      when item_types.SYMLINK
        info.link = @link
    return info

  # -------------------------------------------------------------------------------------------------------------------

  walk_to_array: (_res)->
    ###
    returns an array of all items starting at this point,
    sorted in a predictable way; 
    ###
    _res or= []
    if @item_type is item_types.DIR
      _res.push @signable_info()
      c.walk_to_array(_res) for c in @contents
    else
      _res.push @signable_info()
    return _res

  # -------------------------------------------------------------------------------------------------------------------

  hash_contents: (cb) ->
    h    = new XPlatformHash {alg: 'sha256', encoding: 'hex'}
    fd   = fs.createReadStream @realpath
    await h.hash fd, defer err, hash_res
    cb err, hash_res

# =====================================================================================================================

class Summarizer

  constructor: (opts) ->
    @root_item     =    null
    @presets       =    [] # not the preset names, but the actual instances
    @opts          =    opts or {}
    @opts.ignore   or=  [] # specific files to ignore (such as '/SIGNED.md')
    @opts.presets  or=  [] # the preset names
    @opts.root_dir = path.resolve (@opts.root_dir or '.')
    @_create_presets()

  # -------------------------------------------------------------------------------------------------------------------

  should_ignore: (path_to_file, cb) ->
    res = false
    if path_to_file in @opts.ignore
      res = true
    else
      for p in @presets
        await p.handle @opts.root_dir, path_to_file, defer r
        if r is constants.ignore_res.IGNORE
          res = true
          break
        else if r is constants.ignore_res.DONT_IGNORE
          res = false
          break
    cb null, res

  # -------------------------------------------------------------------------------------------------------------------

  set_root_item: (ri) -> @root_item = ri

  # -------------------------------------------------------------------------------------------------------------------

  root_dir: -> @opts.root_dir

  # -------------------------------------------------------------------------------------------------------------------

  @from_dir: (dir, opts, cb) ->
    ###
    takes the path to a directory and returns a Summarize instance
    ###
    opts            = opts or {}
    opts.root_dir or= dir
    summ            = new Summarizer opts
    err             = null

    root_item = new SummarizedItem {
      fname:            '.'
      parent_path:      ''
      summarizer:       summ
    }
    await root_item.load_traverse defer err
    if not err? then summ.set_root_item root_item
    else
      console.log err
    cb err, summ

  # -------------------------------------------------------------------------------------------------------------------

  hash_match: (h1, h2) -> (not (h1? or h2?)) or (h1?.hash is h2?.hash)

  # -------------------------------------------------------------------------------------------------------------------

  hash_alt_match: (h1, h2) -> (not (h1? or h2?)) or (h1?.hash is h2?.hash) or (h1?.alt_hash is h2?.hash) or (h1?.hash is h2?.alt_hash)

  # -------------------------------------------------------------------------------------------------------------------

  compare_to_json_obj: (obj) ->
    ###
    returns null if they are different; otherwise returns
    {
      wrong:      [files with incorrect hashes, size, or privs]
      missing:    [files that should've been found but weren't]
      orphans:    [files of unknown origin]
      hash_warns: [files that match if line breaks modified]
    }
    ###
    err = 
      missing:    []
      wrong:      []
      orphans:    []
      hash_warns: []

    o1_by_path = {}
    o2_by_path = {}

    o1_by_path[f.path] = f for f in @to_json_obj().found
    o2_by_path[f.path] = f for f in obj.found

    for k,v of o2_by_path
      if not (v2 = o1_by_path[k])?
        err.missing.push v
      else
        ok = true
        for k in ['item_type', 'link', 'exec']
          if (v[k] isnt v2[k]) or not @hash_alt_match(v.hash, v2.hash)
            ok = false
            err.wrong.push {expected: v, got: v2}
        if ok
          if not @hash_match v.hash, v2.hash
            err.hash_warns.push {expected: v, got: v2}
    
    err.orphans.push v for k,v of o1_by_path when not o2_by_path[k]?
 
    if err.missing.length or err.wrong.length or err.orphans.length or err.hash_warns.length
      return err
    else
      return null

  # -------------------------------------------------------------------------------------------------------------------

  to_json_obj: ->
    ###
    a deterministic representation of the summary
    ###
    return {
      meta:
        version: new PackageJson().version()
      ignore:  @opts.ignore
      presets: @opts.presets
      found:   @root_item.walk_to_array()
    }

  # -------------------------------------------------------------------------------------------------------------------

  _create_presets: ->
    # let's make an actual preset for each one requested in the opts
    for p in @opts.presets
      switch p
        when 'git'      then @presets.push new GitPreset()
        when 'dropbox'  then @presets.push new DropboxPreset()
        when 'none'     then continue
        else throw new Error "Unknown preset: #{p}"

    # and a special Globber one for the ignore list
    if @opts.ignore.length
      @presets.push new GlobberPreset @opts.root_dir, @opts.ignore

# =====================================================================================================================

exports.Summarizer = Summarizer

# =====================================================================================================================