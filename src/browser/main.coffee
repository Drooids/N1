global.shellStartTime = Date.now()

app = require 'app'
fs = require 'fs'
path = require 'path'
optimist = require 'optimist'

start = ->
  args = parseCommandLine()

  global.errorReporter = setupErrorReporter(args)

  setupCoffeeScript()

  if process.platform is 'win32'
    SquirrelUpdate = require './squirrel-update'
    squirrelCommand = process.argv[1]
    return if SquirrelUpdate.handleStartupEvent(app, squirrelCommand)

  addPathToOpen = (event, pathToOpen) ->
    event.preventDefault()
    args.pathsToOpen.push(pathToOpen)

  args.urlsToOpen = []
  addUrlToOpen = (event, urlToOpen) ->
    event.preventDefault()
    args.urlsToOpen.push(urlToOpen)

  app.on 'open-file', addPathToOpen
  app.on 'open-url', addUrlToOpen

  app.on 'will-finish-launching', ->
    setupCrashReporter()

  app.on 'ready', ->
    app.removeListener 'open-file', addPathToOpen
    app.removeListener 'open-url', addUrlToOpen

    cwd = args.executedFrom?.toString() or process.cwd()
    args.pathsToOpen = args.pathsToOpen.map (pathToOpen) ->
      if cwd
        path.resolve(cwd, pathToOpen.toString())
      else
        path.resolve(pathToOpen.toString())

    if args.devMode
      require(path.join(args.resourcePath, 'src', 'coffee-cache')).register()
      Application = require path.join(args.resourcePath, 'src', 'browser', 'application')
    else
      Application = require './application'

    Application.open(args)
    console.log("App load time: #{Date.now() - global.shellStartTime}ms") unless args.test

global.devResourcePath = process.env.N1_PATH ? process.cwd()
# Normalize to make sure drive letter case is consistent on Windows
global.devResourcePath = path.normalize(global.devResourcePath) if global.devResourcePath

setupErrorReporter = (args={}) ->
  ErrorReporter = require '../error-reporter'
  return new ErrorReporter({inSpecMode: args.test, inDevMode: args.devMode})

setupCrashReporter = ->
  # In the future, we may want to collect actual native crash reports,
  # but for now let's not send them to GitHub
  # crashReporter.start(productName: "N1", companyName: "Nylas")

setupCoffeeScript = ->
  CoffeeScript = null

  require.extensions['.coffee'] = (module, filePath) ->
    CoffeeScript ?= require('coffee-script')
    coffee = fs.readFileSync(filePath, 'utf8')
    js = CoffeeScript.compile(coffee, filename: filePath)
    module._compile(js, filePath)

parseCommandLine = ->
  version = app.getVersion()
  options = optimist(process.argv[1..])
  options.usage """
    Atom Editor v#{version}

    Usage: atom [options] [path ...]

    One or more paths to files or folders to open may be specified.

    File paths will open in the current window.

    Folder paths will open in an existing window if that folder has already been
    opened or a new window if it hasn't.

    Environment Variables:
    N1_PATH  The path from which Atom loads source code in dev mode.
             Defaults to `cwd`.
  """
  options.alias('d', 'dev').boolean('d').describe('d', 'Run in development mode.')
  options.alias('f', 'foreground').boolean('f').describe('f', 'Keep the browser process in the foreground.')
  options.alias('h', 'help').boolean('h').describe('h', 'Print this usage message.')
  options.alias('l', 'log-file').string('l').describe('l', 'Log all output to file.')
  options.alias('n', 'new-window').boolean('n').describe('n', 'Open a new window.')
  options.alias('r', 'resource-path').string('r').describe('r', 'Set the path to the Atom source directory and enable dev-mode.')
  options.alias('s', 'spec-directory').string('s').describe('s', 'Set the directory from which to run package specs (default: Atom\'s spec directory).')
  options.boolean('safe').describe('safe', 'Do not load packages from ~/.atom/packages or ~/.atom/dev/packages.')
  options.alias('t', 'test').boolean('t').describe('t', 'Run the specified specs and exit with error code on failures.')
  options.alias('v', 'version').boolean('v').describe('v', 'Print the version.')
  options.alias('w', 'wait').boolean('w').describe('w', 'Wait for window to be closed before returning.')
  args = options.argv

  if args.help
    process.stdout.write(options.help())
    process.exit(0)

  if args.version
    process.stdout.write("#{version}\n")
    process.exit(0)

  executedFrom = args['executed-from']
  devMode = args['dev']
  safeMode = args['safe']
  pathsToOpen = args._
  pathsToOpen = [executedFrom] if executedFrom and pathsToOpen.length is 0
  test = args['test']
  specDirectory = args['spec-directory']
  newWindow = args['new-window']
  pidToKillWhenClosed = args['pid'] if args['wait']
  logFile = args['log-file']
  specFilePattern = args['file-pattern']

  if args['resource-path']
    devMode = true
    resourcePath = args['resource-path']
  else
    specsOnCommandLine = true
    # Set resourcePath based on the specDirectory if running specs on atom core
    if specDirectory?
      packageDirectoryPath = path.resolve(specDirectory, '..')
      packageManifestPath = path.join(packageDirectoryPath, 'package.json')
      if fs.statSyncNoException(packageManifestPath)
        try
          packageManifest = JSON.parse(fs.readFileSync(packageManifestPath))
          resourcePath = packageDirectoryPath if packageManifest.name is 'edgehill'
    else
      # EDGEHILL_CORE: if test is given a name, assume that's the package we
      # want to test.
      if test and toString.call(test) is "[object String]"
        if test is "core"
          specDirectory = path.join(global.devResourcePath, "spec")
        else if test is "window"
          specDirectory = path.join(global.devResourcePath, "spec")
          specsOnCommandLine = false
        else
          specDirectory = path.resolve(path.join(global.devResourcePath, "internal_packages", test))

    if devMode
      resourcePath ?= global.devResourcePath

  unless fs.statSyncNoException(resourcePath)
    resourcePath = path.dirname(path.dirname(__dirname))

  # On Yosemite the $PATH is not inherited by the "open" command, so we have to
  # explicitly pass it by command line, see http://git.io/YC8_Ew.
  process.env.PATH = args['path-environment'] if args['path-environment']

  {resourcePath, pathsToOpen, executedFrom, test, version, pidToKillWhenClosed, devMode, safeMode, newWindow, specDirectory, specsOnCommandLine, logFile, specFilePattern}

start()
