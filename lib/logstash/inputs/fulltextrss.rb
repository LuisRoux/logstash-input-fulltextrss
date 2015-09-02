# encoding: utf-8
require "logstash/inputs/base"
require "logstash/namespace"
require "socket" # for Socket.gethostname

# Run command line tools and capture the whole output as an event.
#
# Notes:
#
# * The `@source` of this event will be the command run.
# * The `@message` of this event will be the entire stdout of the command
#   as one event.
#

class LogStash::Inputs::Example < LogStash::Inputs::Base
  config_name "fulltextrss"

  # If undefined, Logstash will complain, even if codec is unused.
  default :codec, "plain" 

  # RSS/Atom feed URL
  config :url, :validate => :string, :required => true

  # Interval to run the command. Value is in seconds.
  config :interval, :validate => :number, :required => true

  # Set how frequently messages should be sent.
  #
  # The default, `1`, means send a message every second.
  config :interval, :validate => :number, :default => 1

  public
  def register
    require "faraday"
    require "rss"
    require 'readability'
    require 'open-uri'

    @logger.info("Registering RSS Input", :url => @url, :interval => @interval)
  end # def register

  def run(queue)
    loop do
      start = Time.now
      @logger.info? && @logger.info("Polling RSS", :url => @url)

      # Pull down the RSS feed using FTW so we can make use of future cache functions
      response = Faraday.get @url
      body = response.body
      # @logger.debug("Body", :body => body)
      # Parse the RSS feed
      feed = RSS::Parser.parse(body, false)
      feed.items.each do |item|
        # Put each item into an event
        @logger.debug("Item", :item => item.author)
        case feed.feed_type
          when 'rss'
            htmlContent = open(item.link).read
	    rbody = Readability::Document.new(htmlContent, :tags => %w[div p img a], :attributes => %w[src href], :remove_empty_nodes => false)
            @codec.decode(rbody.content) do |event|
              event["Feed"] = @url
	      event["feed_type"] = feed.feed_type
	      event["published"] = item.pubDate.utc.iso8601(3)
	      event["title"] = item.title
	      event["link"] = item.link
	      event["author"] = item.author
	      event["images"] = rbody.images
              decorate(event)
              queue << event
            end
	  when 'atom'
            htmlContent = open(item.link.href).read
	    rbody = Readability::Document.new(htmlContent, :tags => %w[div p img a], :attributes => %w[src href], :remove_empty_nodes => false)
            @codec.decode(rbody.content) do |event|
              event["Feed"] = @url
              event["feed_type"] = feed.feed_type
	      if item.published.nil?
	          event["published"] = item.updated.content
	      else
	          event["published"] = item.published.content
	      end
	      event["title"] = item.title.content
	      event["link"] = item.link.href
	      event["author"] = item.author.name.content
	      event["images"] = rbody.images
              decorate(event)
              queue << event
            end
        end
      end
      duration = Time.now - start
      @logger.info? && @logger.info("Command completed", :command => @command,
                                    :duration => duration)

      # Sleep for the remainder of the interval, or 0 if the duration ran
      # longer than the interval.
      sleeptime = [0, @interval - duration].max
      if sleeptime == 0
        @logger.warn("Execution ran longer than the interval. Skipping sleep.",
                     :command => @command, :duration => duration,
                     :interval => @interval)
      else
        sleep(sleeptime)
      end
    end # loop
  end # def run

end # class LogStash::Inputs::Example