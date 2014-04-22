glob_to_regexp = require 'glob-to-regexp'
fs             = require 'fs'
path           = require 'path'
constants      = require '../constants'
PresetBase     = require './preset_base'

# =======================================================================================

class GlobItem

  constructor: (s) ->
    @negation   = false # if this is true, reverses implication of match
    @s          = s     # the original string
    @has_path   = false # whether it has a path defined or runs locally on each file
    @dirs_only  = false # whether it should only match dirs
    @rxx        = null  # the regular expression
    @empty      = false # this is true if this glob item was BS (a comment, empty line, etc)
    @_analyze()

  # --------------------------------------------------------------------------------------

  _analyze: ->
    
    s = @s
      .replace /^[\s]+/g, '' # strip leading whitespace
      .replace /^\#.*/g,  '' # if it's a comment, everything
      .replace /[\s]*$/g, '' # trailing whitespace

    if s[0] is '!'
      @negation = true
      s = s[1...]
    if s[-1...][0] is '/'
      @dirs_only = true
      s = s[...-1]

    if s.length is 0
      @empty = true
    else
      # figure out if it's a path-style regexp
      esc_state = 0
      for c in s
        if (c is '/') and (not esc_state)
          @has_path = true
          break
        else if (c is '\\') and (esc_state is 0)
          esc_state = 1
        else
          esc_state = 0

      console.log "Generated regexp out of '#{escape(s)}', out of '#{escape(@s)}'"
      @rxx = glob_to_regexp s

  # --------------------------------------------------------------------------------------

  does_match: (rel_path, is_a_dir) ->
    # rel_path is relative to some context
    # for the glob
    console.log "Checking #{rel_path} against #{@rxx.toString()}"
    if @empty
      return false
    else if @dirs_only and not is_a_dir
      return false
    else if @rxx.test rel_path
      return true
    else if (not @has_path) and (@rxx.test path.basename rel_path)
      return true
    return false

  # --------------------------------------------------------------------------------------

# =======================================================================================

class GlobberPreset extends PresetBase

  constructor: (working_path, glob_list) ->
    # working_path: where the glob_list is considered relative to.
    # glob_list:    array of strings
    @glob_list    = glob_list
    @working_path = working_path
    @glob_items   = []
    for g in @glob_list
      gi = new GlobItem g
      if not gi.empty
        @glob_items.push gi
      else
        console.log "Skipping glob item '#{g}' "

  # -------------------------------------------------------------------------------------

  handle: (root_dir, path_to_file, cb) ->
    res      = constants.ignore_res.NONE 
    abs_path = path.join root_dir, path_to_file
    rel_path = path.relative @working_path, abs_path
    await @is_a_dir abs_path, defer is_a_dir
    for gi in @glob_items
      if gi.does_match rel_path, is_a_dir
        if gi.negation
          console.log "#{path.relative root_dir, path_to_file} NOT TO BE IGNORED (says #{path.relative root_dir, @working_path})"
          res = constants.ignore_res.DONT_IGNORE
        else
          console.log "#{path.relative root_dir, path_to_file} TO BE IGNORED (says #{path.relative root_dir, @working_path})"
          res = constants.ignore_res.IGNORE
    cb res

  # -------------------------------------------------------------------------------------

  is_a_dir: (p, cb) ->
    await fs.stat p, defer err, stat
    cb stat?.isDirectory()

  # -------------------------------------------------------------------------------------

  # -------------------------------------------------------------------------------------

  @from_file: (f, cb) ->
    full_path       = path.resolve f
    working_path    = path.dirname full_path
    await PresetBase.file_to_array f, defer glob_list
    gp = new GlobberPreset working_path, glob_list
    console.log "Generated globber from #{full_path}; glob_list = [#{glob_list.join ', '}]"

    cb gp

  # -------------------------------------------------------------------------------------

module.exports = GlobberPreset