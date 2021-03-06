// Generated by IcedCoffeeScript 1.7.1-c
(function() {
  var HEADINGS, SPACER, TABLIFY_OPTS, constants, files_from_pretty_format, footer, format_signature, hash_from_str, hash_to_str, item_types, max_depth, parse_signatures, path, pretty_format_files, tablify, utils;

  path = require('path');

  tablify = require('tablify');

  constants = require('./constants');

  item_types = require('./constants').item_types;

  utils = require('./utils');


  /*
  
    A serializer/deserialized for Markdown from codesign objects.
  
    We can switch to jison if basic regexp-style parsing gets out of hand
   */

  HEADINGS = ['size', 'exec', 'file', 'contents'];

  SPACER = '  ';

  TABLIFY_OPTS = {
    show_index: false,
    row_start: '',
    row_end: '',
    spacer: SPACER,
    row_sep_char: ''
  };

  hash_to_str = function(h) {
    if (h.hash === h.alt_hash) {
      return h.hash;
    } else {
      return "" + h.hash + "|" + h.alt_hash;
    }
  };

  hash_from_str = function(s) {
    var hashes;
    hashes = s.split('|');
    return {
      hash: hashes[0],
      alt_hash: hashes[1] || hashes[0]
    };
  };

  max_depth = function(found_files) {
    var f, _i, _len;
    max_depth = 0;
    for (_i = 0, _len = found_files.length; _i < _len; _i++) {
      f = found_files[_i];
      max_depth = Math.max(f._depth, max_depth);
    }
    return max_depth;
  };

  pretty_format_files = function(found_files) {
    var c0, c1, c2, c3, f, i, rows, _i, _len;
    rows = [HEADINGS];
    for (_i = 0, _len = found_files.length; _i < _len; _i++) {
      f = found_files[_i];
      c0 = f.item_type === item_types.FILE ? f.size : '';
      c1 = f.exec ? 'x' : '';
      c2 = ((function() {
        var _j, _ref, _results;
        _results = [];
        for (i = _j = 0, _ref = f._depth; 0 <= _ref ? _j < _ref : _j > _ref; i = 0 <= _ref ? ++_j : --_j) {
          _results.push("  ");
        }
        return _results;
      })()).join('') + utils.escape(f.fname);
      if (f.item_type === item_types.DIR) {
        c2 += "/";
      }
      c3 = (function() {
        switch (f.item_type) {
          case item_types.SYMLINK:
            return "-> " + (utils.escape(f.link));
          case item_types.DIR:
            return '';
          case item_types.FILE:
            if ((f.hash.hash === f.hash.alt_hash) || f.binary) {
              return f.hash.hash;
            } else {
              return "" + f.hash.hash + "|" + f.hash.alt_hash;
            }
        }
      })();
      rows.push([c0, c1, c2, c3]);
    }
    return tablify(rows, TABLIFY_OPTS);
  };

  files_from_pretty_format = function(str_arr) {
    var a0, a1, a2, a3, b0, b1, b2, b3, c0, c1, c2, c3, dir_queue, fname, i, idiff, indent_level, info, last_indent_level, parent_path, r0, res, s, _i, _j, _len, _ref, _ref1, _ref2, _ref3, _ref4;
    res = [];
    r0 = str_arr[0];
    dir_queue = [];
    last_indent_level = 0;
    _ref = [r0.indexOf(HEADINGS[0]), r0.indexOf(HEADINGS[1]) - SPACER.length], a0 = _ref[0], b0 = _ref[1];
    _ref1 = [r0.indexOf(HEADINGS[1]), r0.indexOf(HEADINGS[2]) - SPACER.length], a1 = _ref1[0], b1 = _ref1[1];
    _ref2 = [r0.indexOf(HEADINGS[2]), r0.indexOf(HEADINGS[3]) - SPACER.length], a2 = _ref2[0], b2 = _ref2[1];
    _ref3 = [r0.indexOf(HEADINGS[3]), r0.length], a3 = _ref3[0], b3 = _ref3[1];
    _ref4 = str_arr.slice(1);
    for (_i = 0, _len = _ref4.length; _i < _len; _i++) {
      s = _ref4[_i];
      c0 = s.slice(a0, b0).replace(/(^\s+)|(\s+$)/g, '');
      c1 = s.slice(a1, b1).replace(/(^\s+)|(\s+$)/g, '');
      c2 = s.slice(a2, b2).replace(/(^\s+)|(\s+$)/g, '');
      c3 = s.slice(a3, b3).replace(/(^\s+)|(\s+$)/g, '');
      indent_level = s.slice(a2, b2).match(/[^\s]/).index / SPACER.length;
      fname = utils.unescape(c2).replace(/\/?$/, '');
      if ((idiff = last_indent_level - indent_level) > 0) {
        for (i = _j = 0; 0 <= idiff ? _j < idiff : _j > idiff; i = 0 <= idiff ? ++_j : --_j) {
          dir_queue.pop();
        }
      }
      last_indent_level = indent_level;
      parent_path = dir_queue.join('/');
      info = {
        fname: fname,
        parent_path: parent_path,
        path: parent_path.length ? "" + parent_path + "/" + fname : fname,
        exec: false
      };
      if (c3 === '') {
        info.item_type = item_types.DIR;
        dir_queue.push(fname);
        last_indent_level += 1;
      } else if (c3.slice(0, 2) === '->') {
        info.item_type = item_types.SYMLINK;
        info.link = utils.unescape(c3.slice(3));
      } else {
        info.hash = hash_from_str(c3);
        info.item_type = item_types.FILE;
        info.size = parseInt(c0);
        info.exec = c1 === 'x';
      }
      res.push(info);
    }
    return res;
  };

  format_signature = function(s) {
    return "##### Signed by " + s.signer + "\n```\n" + s.signature + "\n```";
  };

  parse_signatures = function(sig_region) {
    var match, res, rxx;
    res = [];
    rxx = /\#\#\#\#\#\sSigned\sby\s([^\n\r\s]*)\s*```([^`]*)```\s*/g;
    while ((match = rxx.exec(sig_region))) {
      res.push({
        signer: match[1].replace(/(^[\s]*)|([\s]*$)|(\r)/g, ''),
        signature: match[2].replace(/(^[\s]*)|([\s]*$)|(\r)/g, '')
      });
    }
    return res;
  };

  footer = function(o) {
    var msg, ns, poss;
    ns = o.signatures.length;
    if (ns !== 1) {
      msg = "" + ns + " signatures attached are valid";
      poss = "signers'";
    } else {
      msg = "signature attached is valid";
      poss = "signer's";
    }
    return "<hr>\n\n#### Notes\n\nWith keybase you can sign any directory's contents, whether it's a git repo,\nsource code distribution, or a personal documents folder. It aims to replace the drudgery of:\n\n  1. comparing a zipped file to a detached statement\n  2. downloading a public key\n  3. confirming it is in fact the author's by reviewing public statements they've made, using it\n\nAll in one simple command:\n\n```bash\nkeybase dir verify\n```\n\nThere are lots of options, including assertions for automating your checks.\n\nFor more info, check out https://keybase.io/docs/command_line/code_signing";
  };

  exports.to_md = function(o) {
    var file_list, ignore_list, p, preset_list, res, s, signatures;
    ignore_list = ((function() {
      var _i, _len, _ref, _results;
      _ref = o.ignore;
      _results = [];
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        s = _ref[_i];
        _results.push(utils.escape(s));
      }
      return _results;
    })()).join('\n');
    file_list = pretty_format_files(o.found);
    preset_list = tablify((function() {
      var _i, _len, _ref, _results;
      _ref = o.presets;
      _results = [];
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        p = _ref[_i];
        _results.push([p, "# " + constants.presets[p]]);
      }
      return _results;
    })(), TABLIFY_OPTS);
    signatures = ((function() {
      var _i, _len, _ref, _results;
      _ref = o.signatures;
      _results = [];
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        s = _ref[_i];
        _results.push(format_signature(s));
      }
      return _results;
    })()).join('\n\n');
    res = "" + signatures + "\n\n<!-- END SIGNATURES -->\n\n### Begin signed statement \n\n#### Expect\n\n```\n" + file_list + "\n```\n\n#### Ignore\n\n```\n" + ignore_list + "\n```\n\n#### Presets\n\n```\n" + preset_list + "\n```\n\n<!-- summarize version = " + o.meta.version + " -->\n\n### End signed statement\n\n" + (footer(o));
    return res;
  };

  exports.from_md = function(str) {
    var f, file_rows, ignore_rows, match, preset_rows, rxx, signatures, version;
    rxx = /^\s*([^\<]*)\s*\<\!--\sEND\sSIGNATURES\s--\>\s*\#\#\#\sBegin\ssigned\sstatement\s*\#\#\#\#\sExpect\s*```([^`]*)```\s*\#\#\#\#\sIgnore\s*```([^`]*)```\s*\#\#\#\#\sPresets\s*```([^`]*)```\s*\<\!--[\s]*summarize[\s]*version[\s]*=[\s]*([0-9a-z\.]*)[\s]*-->\s*\#\#\#\sEnd\ssigned\sstatement\s*[\s\S]*\s*$/;
    match = rxx.exec(str);
    if (match != null) {
      signatures = match[1];
      file_rows = match[2].split(/\r?\n/).slice(1, -1);
      ignore_rows = match[3].split(/\r?\n/).slice(1, -1);
      preset_rows = match[4].split(/\r?\n/).slice(1, -1);
      version = match[5];
      preset_rows = (function() {
        var _i, _len, _results;
        _results = [];
        for (_i = 0, _len = preset_rows.length; _i < _len; _i++) {
          f = preset_rows[_i];
          _results.push(f.replace(/\s*(\#.*)?\s*$/g, ''));
        }
        return _results;
      })();
      return {
        found: files_from_pretty_format(file_rows),
        ignore: (function() {
          var _i, _len, _results;
          _results = [];
          for (_i = 0, _len = ignore_rows.length; _i < _len; _i++) {
            f = ignore_rows[_i];
            if (f.length) {
              _results.push(f);
            }
          }
          return _results;
        })(),
        presets: preset_rows,
        meta: {
          version: version
        },
        signatures: parse_signatures(signatures)
      };
    } else {
      return null;
    }
  };

}).call(this);
