module Imdb
  # Represents someone on IMDB.com
  class Person
    attr_accessor :id, :url, :name, :avatar_url, :bio, :images, :video_urls, :name_alias

    # Initialize a new IMDB person object with it's IMDB id (as a String)
    #
    #   person = Imdb::Person.new("0000246")
    #
    # Imdb::Person objects are lazy loading, meaning that no HTTP request
    # will be performed when a new object is created. Only when you use an
    # accessor that needs the remote data, a HTTP request is made (once).
    #
    def initialize(imdb_id, preset_attributes = {})
      @id  = imdb_id
      @url = "http://akas.imdb.com/name/#{imdb_id}"

      preset_attributes.each_pair do |attr, val|
        instance_variable_set "@#{attr}", val.to_s.gsub(/"/, '').strip if val rescue nil
      end
    end

    # Returns the URL of person's avatar
    def avatar_url
      @avatar_url ||= document.at("#name-poster").attr('src') rescue nil
    end

    # Returns a string containing the name
    def name(force_refresh = false)
      if @name && !force_refresh
        @name
      else
        @name = document.at('h1').text.strip rescue nil
      end
    end

    # Returns a string containing the birthdate
    def birthdate
      document.css('time[itemprop=birthDate]').text.delete("\n").squeeze("\s").strip
    end

    # Returns an integer containing the age
    def age
      Date.today.year - birthdate[/\d+$/].to_i
    end

    # Returns array of work categories exercised by person, e.g. actor, director, etc.
    def categories
      document.css('#jumpto a').map(&:text)
    end

    # Returns array of movies with person in some category, e.g. as an actor, director, etc.
    def movies_as(category)
      movies = document.css("#filmo-head-#{category.downcase}").first.next_element.children.to_a
      movies.reject! { |movie| movie.class == Nokogiri::XML::Text }
      movies.map do |movie|
        movie_id = movie.attr('id')[/\d+/]
        Movie.new(movie_id)
      end
    end

    def bio
      unless @bio
        bio_text = bio_document.css("#bio_content .soda p").inner_html.gsub(/<i.*/im, '').strip.imdb_unescape_html

        @bio = if block_given?
                 yield bio_text
               else
                 bio_text
               end
      end

      @bio
    end

    def images(limit=10)
      @images ||= photo_gallery_document.css("#media_index_thumbnail_grid a")[0..limit].map do |image_link|
        large_url = "http://akas.imdb.com/#{image_link.attr('href')}"

        { thumb: image_link.children[0].attr('src'), large: Nokogiri::HTML(open(large_url)).at("img#primary-img").attr('src') } rescue {}
      end rescue []
    end

    def video_urls
      @videos ||= video_gallery_document.css(".results-item a:first-child").map do |video_link|
        if video_id = video_link.attr("data-video")
          urls        = {}
          urls[:page] ="http://akas.imdb.com/video/imdb/#{video_id}"
          urls[:embed]="http://www.imdb.com/video/imdb/#{video_id}/imdb/embed"

          urls
        end
      end.compact rescue []
    end

    private

    # Returns a new Nokogiri document for parsing.
    def document
      @document ||= Nokogiri::HTML(Imdb::Person.find_by_id(@id))
    end

    # Returns a new Nokogiri document for parsing.
    def bio_document
      @bio_document ||= Nokogiri::HTML(Imdb::Person.find_by_id(@id, 'bio'))
    end

    # Returns a new Nokogiri document for parsing.
    def photo_gallery_document
      @photo_gallery_document ||= Nokogiri::HTML(Imdb::Person.find_by_id(@id, 'mediaindex'))
    end

    # Returns a new Nokogiri document for parsing.
    def video_gallery_document
      @video_gallery_document ||= Nokogiri::HTML(Imdb::Person.find_by_id(@id, 'videogallery'))
    end

    # Use HTTParty to fetch the raw HTML for this person.
    def self.find_by_id(imdb_id, page=nil)
      unless page
        open("http://akas.imdb.com/name/#{imdb_id}")
      else
        open("http://akas.imdb.com/name/#{imdb_id}/#{page}")
      end
    end

    # Dynamic aliasing for movies_as method. e.g. movies_as_actor equals movies_as(:actor)
    def method_missing(method_name, *args)
      get_movies = method_name.to_s.match(/^movies_as_(.+)$/)
      category = get_movies[1] if get_movies
      if get_movies && categories.map(&:downcase).include?(category.gsub(/_/, ' '))
        movies_as category
      else
        super
      end
    end
  end # Person
end # Imdb
