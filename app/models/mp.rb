require 'hpricot'
require 'open-uri'

class Mp < ActiveRecord::Base
  SIMILARITY_COLUMNS = [ :name, :riding_id ]

  attr_accessor :upload_image_url

  before_validation :download_remote_image, :if => Proc.new { |mp| mp.upload_image_url.present? }

  index do
    parl_gc_id
    parl_gc_constituency_id
    name
    email
    website
    parliamentary_phone
    parliamentary_fax
    constituency_address
    constituency_city
    constituency_postal_code
    constituency_phone
    constituency_fax
  end

  has_attached_file :image,
                    :styles      => { :medium => "120x120>", :small => "40x40>" },
                    :storage     => :s3,
                    :path        => ":rails_env/:attachment/:id/:style.:extension",
                    :default_url => "/images/placeholder_photo_:style.gif",
                    :bucket      => 'citizen_factory',
                    :s3_credentials => {:access_key_id => ENV["AWS_ACCESS_KEY_ID"], :secret_access_key => ENV["AWS_SECRET_ACCESS_KEY"]}

  has_and_belongs_to_many :postal_codes
  has_many :recorded_votes, :include => ["vote","mp"]
  #has_many :parliamentary_functions
  has_many :current_parliamentary_functions, :class_name => "ParliamentaryFunction", :conditions => "end_date IS NULL"
  #has_many :committees, :class_name => "CommitteeMembership", :include => "committee"
  has_many :current_committees, :class_name => "CommitteeMembership", :conditions => "parliament = #{ENV['CURRENT_PARLIAMENT'].to_i} AND session = #{ENV['CURRENT_SESSION'].to_i}"
  has_many :election_results, :include => "election"
  has_many :tweets, :order => "created_at DESC"
  belongs_to :province
  belongs_to :riding, :include => "province"
  belongs_to :party
  has_and_belongs_to_many :news_articles, :join_table => 'mps_news_articles'

  named_scope :active, :conditions => {:active => true}

  class << self
    def find_by_constituency_name_and_last_name(constituency_name, lastname)
      mps = find :all, :include => [:riding], :conditions => {'ridings.name_en' => constituency_name}
      mps.detect {|mp| mp.name =~ /#{lastname}$/}
    end

    def similar
      all(
        :select => "mps.*, #{similarity_hash('mps')} AS similarity_hash",
        :from => "(
          SELECT name, riding_id, active, MAX(parl_gc_id) AS parl_gc_id
          FROM mps AS mp1
          WHERE (
            SELECT COUNT(*)
            FROM mps AS mp2
            WHERE #{similarity_hash('mp2')} = #{similarity_hash('mp1')}
          ) > 1
          GROUP BY name, riding_id, active
        ) AS t",
        :joins => "INNER JOIN mps ON mps.parl_gc_id = t.parl_gc_id",
        :order => "t.name DESC, t.riding_id, t.active DESC"
      ).group_by(&:similarity_hash)
    end

    def similarity_hash(prefix)
      columns = SIMILARITY_COLUMNS.map { |column| "#{prefix}.#{column}" }
      "MD5(#{columns.join(' || ')})"
    end
  end

  def merge(mp)
    basic_attributes = [ :date_of_birth, :place_of_birth, :wikipedia, :wikipedia_riding, :facebook, :twitter ]
    basic_attributes.each do |attr|
      self.send("#{attr}=", mp.send(attr)) unless self.send(attr).present?
    end

    self.upload_image_url = mp.image.url if default_image? && !mp.default_image?
  end

  def age
    now = Time.now.utc.to_date
    return date_of_birth ? now.year - date_of_birth.year - (date_of_birth.to_date.change(:year => now.year) > now ? 1 : 0) : nil
  end

  def recorded_vote_for(vote)
    recorded_votes.find_by_vote_id(vote.id) || recorded_votes.new
  end

  def links
    h = {}
    h[I18n.t('members.weblink.facebook', :member_name => name)]         = facebook                        unless facebook.blank?
    h[I18n.t('members.weblink.wikipedia', :member_name => name)]        = wikipedia                       unless wikipedia.blank?
    h[I18n.t('members.weblink.wikipedia_riding', :member_name => name)] = wikipedia_riding                unless wikipedia_riding.blank?
    h[I18n.t('members.weblink.twitter', :member_name => name)]          = "http://twitter.com/#{twitter}" unless twitter.blank?
    h[I18n.t('members.weblink.personal', :member_name => name)]         = website                         unless website.blank?
    h
  end

  def hansard_statements(limit)
    HansardStatement.find_by_sql(["SELECT * FROM hansard_statements WHERE member_name = ? ORDER BY time DESC LIMIT ?;", name, limit])
  end

  def fetch_new_tweets
    tweets = []
    url = "http://search.twitter.com/search.json?q=from:#{twitter}"
    begin
      open(url) { |f|
        JSON.parse(f.read)['results'].each { |result|
          if not Tweet.find_by_twitter_id(result['id'])
            tweet = Tweet.create({
              :mp_id => id,
              :text => result['text'],
              :created_at => result['created_at'],
              :twitter_id => result['id']
            })
            tweets << tweet
          end
        }
      }
    rescue
    end
    return tweets
  end

  def fetch_news_articles
    term = %Q{#{name} AND ("MP" OR "Member of Parliament") location:Canada}
    GoogleNews.search(term)
  end

  def update_news_articles
    articles = fetch_news_articles
    ids = news_articles.all(
      :select => :id,
      :conditions => { :id => articles }
    ).map(&:id)

    new_articles = articles.reject { |a| ids.include?(a.id) }
    news_articles << new_articles
    save

    new_articles
  end

  def default_image?
    image.url(:original) == '/images/placeholder_photo_original.gif'
  end

  private

  def download_remote_image
    self.image = open(upload_image_url)
  end
end
