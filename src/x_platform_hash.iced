crypto  = require 'crypto'
rstream = require 'replacestream'

###

  XPlatform hash returns a dict like this:
  {
    hash:     <some_str>
    alt_hash: <some_str>
  }

  alt_hash is the hash with '\r\n' replaced with '\n' thoughout a file.

###

class XPlatformHash

  constructor: (opts) ->
    opts      = opts          or {}
    @alg      = opts.alg      or 'sha256'
    @encoding = opts.encoding or 'hex'

  # ------------------------------------------------------------------------------------------------------------------

  hash: (read_stream, cb) ->
    hash     = crypto.createHash   @alg
    alt_hash = crypto.createHash   @alg
    hash.setEncoding     @encoding
    alt_hash.setEncoding @encoding

    read_stream.on 'end', ->
      hash.end()
      alt_hash.end()
      cb null, {hash: hash.read(), alt_hash: alt_hash.read()}
    read_stream.on 'error', (e) -> cb e, null
    read_stream.pipe hash
    read_stream.pipe(rstream('\r\n', '\n')).pipe alt_hash

  # ------------------------------------------------------------------------------------------------------------------

  hash_str: (str, cb) ->
    alt_str = str.replace /\r/g, ''
    cb null,
      hash:     crypto.createHash(@alg).update(str).digest     @encoding
      alt_hash: crypto.createHash(@alg).update(alt_str).digest @encoding

# =====================================================================================================================

module.exports = XPlatformHash