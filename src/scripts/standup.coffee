# Description:
#   Agile standup bot ala tender
#
# Commands:
#   hubot standup help - show help for the standup
#   hubot <who> is a member of <team> - tell hubot who is the member of <team>'s standup
#   hubot standup [for <team>] - start the standup for <team>
#   hubot cancel standup - cancel the current standup
#   hubot skip <who> - skip someone when they're not available
#  [hubot] next - say when your updates for the standup is done
#
# Author:
#   @miyagawa

module.exports = (robot) ->
  robot.respond /(?:cancel|stop) standup *$/i, (msg) ->
    delete robot.brain.data.standup?[msg.message.user.room]
    msg.send "Standup cancelled"

  robot.respond /standup\b( for (.*))? *$/i, (msg) ->
    room  = msg.message.user.room
    group = msg.match[2].trim() or 'devs'
    if robot.brain.data.standup?[room]
      msg.send "The standup for #{robot.brain.data.standup[room].group} is in progress! Cancel it first with 'cancel standup'"
      return

    attendees = []
    for own key, user of robot.brain.data.users
      roles = user.roles or [ ]
      if "a #{group} member" in roles or "an #{group} member" in roles or "a member of #{group}" in roles
        attendees.push user
    if attendees.length > 0
      robot.brain.data.standup or= {}
      robot.brain.data.standup[room] = {
        group: group,
        start: new Date().getTime(),
        attendees: attendees,
        remaining: attendees,
        log: [],
      }
      who = attendees.map((user) -> user.name).join(', ')
      msg.send "Ok, let's start the standup: #{who}"
      nextPerson robot, room, msg
    else
      msg.send "Oops, can't find anyone with 'a #{group} member' role!"

  robot.respond /(?:that\'s it|next(?: person)?|done) *$/i, (msg) ->
    unless robot.brain.data.standup?[msg.message.user.room]
      return
    if robot.brain.data.standup[msg.message.user.room].current.id isnt msg.message.user.id
      msg.reply "but it's not your turn! Use skip [someone] or next [someone] instead."
    else
      nextPerson robot, msg.message.user.room, msg

  robot.hear /^\s*(?:that\'?s\s+it|next\s+(?:person|one)?|done|(Я|у\s+меня|вроде)\s+вс[её])([.!]*) *$/i, (msg) ->
    unless robot.brain.data.standup?[msg.message.user.room]
      return
    if robot.brain.data.standup[msg.message.user.room].current.id is msg.message.user.id
      nextPerson robot, msg.message.user.room, msg

  robot.respond /(skip|next) (.*) *$/i, (msg) ->
    unless robot.brain.data.standup?[msg.message.user.room]
      return

    is_skip = msg.match[1] == 'skip'
    users = robot.brain.usersForFuzzyName msg.match[2]
    if users.length is 1
      skip = users[0]
      standup = robot.brain.data.standup[msg.message.user.room]
      if is_skip
        standup.remaining = (user for user in standup.remaining when user.name != skip.name)
        if standup.current.id is skip.id
          nextPerson robot, msg.message.user.room, msg
        else
          msg.send "Ok, I will skip #{skip.name}"
      else
        if standup.current.id is skip.id
          standup.remaining.push skip
          nextPerson robot, msg.message.user.room, msg
        else
          msg.send "But it is not #{skip.name}'s turn!"
    else if users.length > 1
      msg.send "Be more specific, I know #{users.length} people named like that: #{(user.name for user in users).join(", ")}"
    else
      msg.send "#{msg.match[2]}? Never heard of 'em"

  robot.respond /standup\s+help\s*$/i, (msg) ->
    msg.send """
             <who> is a member of <team> - tell hubot who is the member of <team>'s standup
             standup [for <team>] - start the standup for <team>
             cancel standup - cancel the current standup
             skip <who> - skip someone when they're not available
             next - say when your updates for the standup is done
             """

  robot.catchAll (msg) ->
    unless robot.brain.data.standup?[msg.message.user.room]
      return
    robot.brain.data.standup[msg.message.user.room].log.push { message: msg.message, time: new Date().getTime() }

nextPerson = (robot, room, msg) ->
  standup = robot.brain.data.standup[room]
  if standup.remaining.length == 0
    howlong = calcMinutes(new Date().getTime() - standup.start)
    msg.send "All done! Standup was #{howlong}."
    robot.brain.emit 'standupLog', standup.group, room, msg, standup.log
    delete robot.brain.data.standup[room]
  else
    standup.current = standup.remaining.shift()
    msg.send "#{addressUser(standup.current.name, robot.adapter)} your turn"

addressUser = (name, adapter) ->
  className = adapter.__proto__.constructor.name
  switch className
    when "HipChat", "SlackBot" then "@#{name.replace(' ', '')}"
    else "#{name}:"

calcMinutes = (milliseconds) ->
  seconds = Math.floor(milliseconds / 1000)
  if seconds > 60
    minutes = Math.floor(seconds / 60)
    seconds = seconds % 60
    "#{minutes} minutes and #{seconds} seconds"
  else
    "#{seconds} seconds"
