{View} = require('atom-space-pen-views')
packageName = require '../utils/package-helper'

CompositeDisposable = null
shell = null
$ = null
SettingsHelper = null
spark = null

module.exports =
class StatusBarView extends View
  @content: ->
    @div =>
      @div id: 'logo-tile', class: "#{packageName()} inline-block", outlet: 'logoTile', =>
        @img src: "atom://#{packageName()}/images/logo.png"
      @div id: 'login-status-tile', class: "#{packageName()} inline-block", outlet: 'loginStatusTile'
      @div id: 'current-device-tile', class: "#{packageName()} inline-block hidden", outlet: 'currentCoreTile', =>
        @span class: 'platform-icon', outlet: 'platformIcon', title: 'Current target platform', =>
          @a click: 'selectCore'
      @span id: 'compile-status-tile', class: "#{packageName()} inline-block hidden", outlet: 'compileStatusTile', =>
        @span id: 'compile-working', =>
          @span class: 'three-quarters'
          @a 'Compiling in the cloud...'
        @a id: 'compile-failed', click: 'showErrors', class:'icon icon-stop'
        @a id: 'compile-success', click: 'showFile', class:'icon icon-check'
      @span id: 'log-tile', class: "#{packageName()} inline-block", outlet: 'logTile'

  initialize: (serializeState) ->
    {$} = require('atom-space-pen-views')
    {CompositeDisposable} = require 'atom'

    @disposables = new CompositeDisposable
    @workspaceElement = atom.views.getView(atom.workspace)

    SettingsHelper = require '../utils/settings-helper'

    @getAttributesPromise = null
    @interval = null

    # Defaults to Core
    @platformIcon.addClass 'platform-icon-0'

    commands = {}
    commands["#{packageName()}:update-login-status"] = => @updateLoginStatus()
    commands["#{packageName()}:update-core-status"] = => @updateCoreStatus()
    commands["#{packageName()}:update-compile-status"] = => @updateCompileStatus()
    @disposables.add atom.commands.add 'atom-workspace', commands

  # Returns an object that can be retrieved when package is activated
  serialize: ->

  # Tear down any state and detach
  destroy: ->

  addTiles: (statusBar) ->
    statusBar.addLeftTile(item: @logoTile, priority: 100)
    statusBar.addLeftTile(item: @loginStatusTile, priority: 100)
    statusBar.addLeftTile(item: @currentCoreTile, priority: 100)
    statusBar.addLeftTile(item: @compileStatusTile, priority: 100)
    statusBar.addLeftTile(item: @logTile, priority: 100)

  # Callback triggering selecting core command
  selectCore: ->
    atom.commands.dispatch @workspaceElement, "#{packageName()}:select-device"

  # Callback triggering showing compile errors command
  showErrors: =>
    atom.commands.dispatch @workspaceElement, "#{packageName()}:show-compile-errors"

  # Opening file in Finder/Explorer
  showFile: =>
    shell ?= require 'shell'
    rootPath = atom.project.getPaths()[0]
    compileStatus = SettingsHelper.getLocal 'compile-status'
    shell.showItemInFolder rootPath + '/' + compileStatus.filename

  # Get current core's status from the cloud
  getCurrentCoreStatus: ->
    if !SettingsHelper.hasCurrentCore()
      return

    statusElement = @currentCoreTile.find('a')
    @currentCoreTile.removeClass 'online'

    spark = require 'spark'
    spark.login { accessToken: SettingsHelper.get('access_token') }
    @getAttributesPromise = spark.getAttributes SettingsHelper.getLocal('current_core')
    @getAttributesPromise.then (e) =>
      SettingsHelper.setLocal 'variables', {}
      SettingsHelper.setLocal 'functions', []

      if !e
        return

      # Check if current core is still available
      if e.error
        SettingsHelper.clearCurrentCore()
        clearInterval @interval
        @interval = null
        @updateCoreStatus()
      else
        if e.connected
          @currentCoreTile.addClass 'online'

        SettingsHelper.setLocal 'current_core_name', e.name
        if !e.name
          statusElement.text 'Unnamed'
        else
          statusElement.text e.name

        SettingsHelper.setLocal 'variables', e.variables
        SettingsHelper.setLocal 'functions', e.functions

        # Periodically check if core is online
        if !@interval
          @interval = setInterval =>
            @updateCoreStatus()
          , 30000

      atom.commands.dispatch @workspaceElement, "#{packageName()}:core-status-updated"
      @getAttributesPromise = null

    , (e) =>
      console.error e

      atom.commands.dispatch @workspaceElement, "#{packageName()}:core-status-updated"
      @getAttributesPromise = null

  # Update current core's status
  updateCoreStatus: ->
    statusElement = @currentCoreTile.find('a')
    @platformIcon.removeClass()
    @platformIcon.addClass 'platform-icon'

    if SettingsHelper.hasCurrentCore()
      currentCore = SettingsHelper.getLocal('current_core_name')
      if !currentCore
        currentCore = 'Unnamed'
      statusElement.text currentCore
      @platformIcon.addClass 'platform-icon-' + SettingsHelper.getLocal('current_core_platform')

      @getCurrentCoreStatus()
    else
      @currentCoreTile.removeClass 'online'
      statusElement.text 'No devices selected'
      @platformIcon.addClass 'platform-icon-0'

  # Update login status
  updateLoginStatus: ->
    @loginStatusTile.empty()

    if SettingsHelper.isLoggedIn()
      username = SettingsHelper.get('username')
      @loginStatusTile.text(username)

      @currentCoreTile.removeClass 'hidden'
      @updateCoreStatus()
    else
      loginButton = $('<a/>').text('Click to log in to Particle Cloud...')
      @loginStatusTile.append loginButton
      loginButton.on 'click', =>
        atom.commands.dispatch @workspaceElement, "#{packageName()}:login"

      @currentCoreTile.addClass 'hidden'

    atom.commands.dispatch @workspaceElement, "#{packageName()}:update-menu"

  updateCompileStatus: ->
    @compileStatusTile.addClass 'hidden'
    compileStatus = SettingsHelper.getLocal 'compile-status'

    if !!compileStatus
      @compileStatusTile.removeClass 'hidden'
      @compileStatusTile.find('>').hide()

      if !!compileStatus.working
        @compileStatusTile.find('#compile-working').show()
      else if !!compileStatus.errors
        subElement = @compileStatusTile.find('#compile-failed')
        if compileStatus.errors.length == 1
          subElement.text('One error')
        else
          subElement.text(compileStatus.errors.length + ' errors')
        subElement.show()
      else if !!compileStatus.error
        subElement = @compileStatusTile.find('#compile-failed')
        subElement.text(compileStatus.error)
        subElement.show()
      else
        @compileStatusTile.find('#compile-success')
                          .text('Success!')
                          .show()

  setStatus: (text, type = null) ->
      @logTile.text(text)
        .removeClass()

      if type
        @logTile.addClass('text-' + type)

  clear: ->
    @logTile.fadeOut =>
      @setStatus ''
      @logTile.show()

  clearAfter: (delay) ->
    setTimeout =>
      @clear()
    , delay
