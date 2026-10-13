# frozen_string_literal: true

require "erb"
require "nokogiri"

@game = { "title" => "测试游戏", "origin" => "https://bonk.muwei.xyz" }
@nonce = "test-nonce"
@ticket = "synthetic-ticket"
@state = "synthetic-state"
@room = "sample-room"
template = File.expand_path("../app/views/black_room_games/games/open.html.erb", __dir__)
doc = Nokogiri.HTML(ERB.new(File.read(template)).result(binding))
unless doc.at_css("style")["nonce"] == @nonce && doc.at_css("script")["nonce"] == @nonce
  raise "nonce missing"
end
form = doc.at_css("form")
unless form["method"] == "post" && form["action"] == "https://bonk.muwei.xyz/_blackroom/open"
  raise "wrong form"
end
{ "ticket" => @ticket, "browser_state" => @state, "room" => @room }.each do |name, value|
  raise "missing POST field" unless form.at_css("input[name=#{name}]")["value"] == value
end
raise "missing manual fallback" unless form.at_css("button[type=submit]")
raise "missing reduced motion" unless doc.at_css("style").text.match?(/prefers-reduced-motion/)
raise "missing accessible status" unless doc.at_css("[role=status][aria-live=polite]")
unless doc.at_css("script").text.strip == 'document.getElementById("game-launch").submit();'
  raise "delayed launch"
end
raise "external resource" unless doc.css("script[src], link[href], img[src], iframe").empty?
puts "transition nonce, native POST, accessible loading and immediate submission passed"
