#!/usr/bin/env coffee

# The command line utility. Gets installed as swbox by the magic of package.json

fs = require 'fs'
wd = require 'wd'
Mocha = require 'mocha'
# Magically, means that mocha can run tests written in CoffeeScript.
require 'coffee-script'

VERSION = require('./package').version

{spawn, exec} = require 'child_process'

write = (text) ->
  process.stdout.write "#{text}\n"

warn = (text) ->
  process.stderr.write "#{text}\n"

showVersion = ->
  write "swbox #{VERSION}"
  write '© ScraperWiki Limited, AGPL Licensed'

showHelp = ->
    write 'swbox:  A command line interface for interacting with ScraperWiki boxes'
    write 'Usage:  swbox command <required_argument> [optional_argument]'
    write 'Commands:'
    write '    swbox clone <boxName>        Make a local copy of the entire contents of <boxName>'
    write '    swbox push [--preview]       Push changes from a local clone back up to the original box'
    write '    swbox mount <boxName>        Mount <boxName> as an sshfs drive'
    write '    swbox unmount <boxName>      Unmount the <boxName> sshfs drive'
    write '    swbox test                   Run the tests inside this box'
    write '    swbox [-v|--version]         Show version & license info'
    write '    swbox help                   Show this documentation'
    write 'Examples:'
    write '    swbox clone fegy5tq          Makes a local copy of fegy5tq@box.scraperwiki.com'
    write '    swbox clone g6ut126@free     Makes a local copy of g6ut126@free.scraperwiki.com'

mountBox = ->
  args = process.argv[3..]
  if args.length == 1
    [ boxName, boxServer ] = getBoxNameAndServer(args)
    path = "/tmp/ssh/#{boxName}"
    exec "mkdir -p #{path} && sshfs #{boxName}@#{boxServer}.scraperwiki.com:. #{path} -ovolname=#{boxName} -oBatchMode=yes -oworkaround=rename,noappledouble", {timeout: 5000}, (err, stdout, stderr) ->
      if err?
        if "#{err}".indexOf('sshfs: command not found') > -1
          warn 'sshfs is not installed!'
          warn 'You can find it here: http://osxfuse.github.com'
        else if "#{err}".indexOf('remote host has disconnected') > -1
          warn 'Error: The box server did not respond.'
          warn "The box ‘#{boxName}’ might not exist, or your SSH key might not be associated with it."
          warn 'Make sure you can see the box in your Data Hub on http://scraperwiki.com'
          exec "rmdir #{path}", (err) ->
            if err? then warn "Additionally, we enountered an error while removing the temporary directory at #{path}"
        else
          warn 'Unexpected error:'
          warn err
      else
        write "Box mounted:\t#{path}"
  else
    write 'Please supply exactly one <boxName> argument'
    write 'Usage:'
    write '    swbox mount <boxName>    Mount <boxName> as an sshfs drive'

unmountBox = ->
  args = process.argv[3..]
  if args.length == 1
    [ boxName, boxServer ] = getBoxNameAndServer(args)
    path = "/tmp/ssh/#{boxName}"
    exec "umount #{path}", (err, stdout, stderr) ->
      if err?
        if "#{err}".indexOf 'not currently mounted' > -1
          warn "Error: #{boxName} is not currently mounted"
        else
          warn 'Unexpected error:'
          warn err
      else
        write "Box unmounted:\t#{boxName}"
  else
    write 'Please supply exactly one <boxName> argument'
    write 'Usage:'
    write '    swbox unmount <boxName>    Unmount the <boxName> sshfs drive'

cloneBox = ->
  args = process.argv[3..]
  if args.length == 1
    [ boxName, boxServer ] = getBoxNameAndServer(args)
    options = [
      '--archive', # enable recursion and preserve file metadata
      '--verbose', # chatty
      '--one-file-system', # don't cross filesystem boundaries
      "--exclude='.DS_Store'",
      '--delete-excluded', # actually remove excluded files on box
      '-e \'ssh -o "NumberOfPasswordPrompts 0"\'' # use ssh keys only
    ]
    write "Cloning #{boxName}@#{boxServer}.scraperwiki.com into #{process.cwd()}/#{boxName}..."
    command = """rsync #{options.join(' ')} #{boxName}@#{boxServer}.scraperwiki.com:. #{process.cwd()}/#{boxName}"""
    exec command, (err, stdout, stderr) ->
      if stderr.match /^Permission denied/
        warn 'Error: Permission denied.'
        warn "The box ‘#{boxName}’ might not exist, or your SSH key might not be associated with it."
        warn 'Make sure you can see the box in your Data Hub on http://scraperwiki.com'
      else if err
        warn "Unexpected error:"
        warn err
      else if stderr and not stderr.match /Permanently added/
        warn "Unexpected error:"
        warn stderr
      else
        write "Saving settings into #{boxName}/.swbox..."
        settings =
          boxName: boxName
          boxServer: boxServer
        fs.writeFileSync "#{boxName}/.swbox", JSON.stringify(settings, null, 2)
        write "Box cloned to #{boxName}"
  else
    write 'Please supply a <boxName> argument'
    write 'Usage:'
    write '    swbox clone <boxName>    Make a local copy of the entire contents of <boxName>'


nearest = (filename) ->
  """Walk up the directory hierarchy until we find a directory
  containing a file called `filename`. The directory is returned
  as a string. If the file is not found an empty string is
  returned."""

  dir = process.cwd()
  walkUp = ->
    dir = dir.split('/')[..-2].join '/'
  walkUp() until ( dir == '' or fs.existsSync "#{dir}/#{filename}" )
  return dir

pushBox = ->
  dir = nearest ".swbox"
  if dir
    swbox = "#{dir}/.swbox"
    settings = JSON.parse( fs.readFileSync swbox, "utf8" )
    if settings.boxName
      boxName = settings.boxName
      boxServer = settings.boxServer or 'box'
      options = [
        '--archive', # enable recursion and preserve file metadata
        '--verbose', # chatty
        '--one-file-system', # don't cross filesystem boundaries
        '--itemize-changes', # show what's changed
        "--exclude='.DS_Store'",
        '--delete-excluded', # actually remove excluded files on box
        '-e \'ssh -o "NumberOfPasswordPrompts 0"\'' # use ssh keys only
      ]
      if '--preview' in process.argv
        options.push('--dry-run')
      command = """rsync #{options.join(' ')} "#{dir}/" #{boxName}@#{boxServer}.scraperwiki.com:."""
      exec command, (err, stdout, stderr) ->
        if stderr.match /^Permission denied/
          warn 'Error: Permission denied.'
          warn "The box ‘#{boxName}’ might not exist, or your SSH key might not be associated with it."
          warn 'Make sure you can see the box in your Data Hub on http://scraperwiki.com'
        else if err
          warn "Unexpected error:"
          warn err
        else if stderr and not stderr.match /Permanently added/
          warn "Unexpected error:"
          warn stderr
        else
          if '--preview' in process.argv
            write "Previewing changes from #{dir}/ to #{boxName}@#{boxServer}.scraperwiki.com..."
          else
            write "Applying changes from #{dir}/ to #{boxName}@#{boxServer}.scraperwiki.com..."
          rsyncSummary stdout
    else
      warn "Error: Settings file at #{swbox} does not contain a boxName value!"
  else
    warn "Error: I don‘t know where I am!"
    warn "You must run this command from within a local clone of a ScraperWiki box."

rsyncSummary = (output) ->
  # output should be the stdout from an `rsync --itemize-changes` command
  lines = output.split('\n')
  for line in lines
    file = line.replace /^\S+ /, ''
    if line.indexOf('<') == 0
      write "\u001b[32m▲ #{file}\u001b[0m"
    else if line.indexOf('>') == 0
      write "\u001b[33m▼ #{file}\u001b[0m"
    else if line.indexOf('*deleting') == 0
      write "\u001b[31m– #{file}\u001b[0m"

getBoxNameAndServer = (args) ->
  # takes a command line argument list, and returns a boxName and boxServer
  boxNameAndServer = args[0].replace(/@$/, '').split('@')
  if boxNameAndServer.length == 1
    boxNameAndServer.push('box')
  return [ boxNameAndServer[0], boxNameAndServer[1] ]

SELENIUM_PATHS = [
  "selenium-server-standalone-2.35.0.jar",
  "sw/selenium-server-standalone-2.35.0.jar",
  "sw/custard/selenium-server-standalone-2.35.0.jar"
]
CHROMEDRIVER_PATHS = [
  "chromedriver",
  "sw/chromedriver",
  "sw/custard/chromedriver"
]

getNearestSelenium = ->
  ret = null
  for seleniumPath in SELENIUM_PATHS
    path = nearest(seleniumPath)
    if path
      ret = "#{path}/#{seleniumPath}"
      break
  return ret

getNearestChromedriver = ->
  ret = null
  for chromedriverPath in CHROMEDRIVER_PATHS
    path = nearest(chromedriverPath)
    if path
      ret = "#{path}/#{chromedriverPath}"
      break
  return ret

test = ->
  testDir = nearest "test"
  if testDir
    testDir = "#{testDir}/test"
  else
    warn "No tests found. Swbox expects Mocha tests to be placed in this box's /test directory."
    process.exit 2

  # check whether selenium server is running
  wd.remote().status (err, status) ->
    if status
      runMocha(testDir)
    else
      startSelenium (err) ->
        warn err if err
        runMocha(testDir)

startSelenium = (cb) ->
  seleniumPath = getNearestSelenium()
  chromedriverPath = getNearestChromedriver()
  if not seleniumPath
    return cb Error "#{SELENIUM_PATHS[0]} not found. Download it from http://docs.seleniumhq.org/download/ and place it in any of this directory's parents."
  if not chromedriverPath
    return cb Error "chromedriver not found. Download it from http://docs.seleniumhq.org/download/ and place it in any of this directory's parents."

  child = spawn 'java', ['-jar', "#{seleniumPath}", "-Dwebdriver.chrome.driver=#{chromedriverPath}"]

  # We scan all output for messages from java,
  # and call the callback once we see the "Started" message.
  child.on 'error', (err) ->
    if err.code is 'ENOENT'
      cb Error "java not found. Please install it. (sorry)"
    else
      cb err
  child.stderr.on 'data', (data) ->
    if /selenium/.test process.env.SWBOX_DEBUG
      process.stderr.write data
  child.stdout.on 'data', (data) ->
    if /selenium/.test process.env.SWBOX_DEBUG
      process.stdout.write data
    # :todo:(drj) We need to buffer here in case we get
    # "Started " in one data block and "org.openqa..." in another.
    if "#{data}".indexOf('Started org.openqa.jetty.jetty.Server') > -1
      # write "Selenium has started running"
      cb null

runMocha = (testDir) ->
  mocha = new Mocha
    reporter: 'spec'
    timeout: 233000 # really long timeout, because swbox.setup() (logging in) takes ages

  for file in fs.readdirSync(testDir)
    if /\.(js|coffee)$/.test file
      mocha.addFile "#{testDir}/#{file}"

  mocha.run (failures) ->
    process.exit failures

swbox =
  mount: mountBox
  unmount: unmountBox
  clone: cloneBox
  push: pushBox
  help: showHelp
  test: test
  '--help': showHelp
  version: showVersion
  '-v': showVersion
  '--version': showVersion

main = ->
  args = process.argv
  if args.length > 2
    if args[2] of swbox
      swbox[args[2]]()
    else
      write "Sorry, I don’t understand ‘#{args[2]}’"
      write 'Try: swbox help'
  else
    swbox.help()

main()
