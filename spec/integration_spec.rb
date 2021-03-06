require File.expand_path(File.join(File.dirname(__FILE__), 'spec_helper'))
require File.expand_path(File.join(File.dirname(__FILE__), 'integration_spec_conf'))

require 'active_record'
require 'sqlite3'
require 'logger'

FileUtils.rm( 'data.sqlite3' ) rescue nil
ActiveRecord::Base.logger = Logger.new(STDOUT)
ActiveRecord::Base.establish_connection(
    'adapter' => 'sqlite3',
    'database' => 'data.sqlite3',
    'pool' => 5,
    'timeout' => 5000
)

ActiveRecord::Schema.define do
  create_table :products do |t|
    t.string :name
    t.string :href
    t.string :tags
    t.text :description
  end
end

class Product < ActiveRecord::Base
  include Tanker

  tankit 'tanker_integration_tests' do
    indexes :name
    indexes :href
    indexes :tags
    indexes :description
  end
end

describe 'An imaginary store' do

  before(:all) do
    Tanker::Utilities.clear_index('tanker_integration_tests')

    # Google products
    @blackberry = Product.create(:name => 'blackberry', :href => "google", :tags => ['decent', 'businessmen love it'])
    @nokia = Product.create(:name => 'nokia', :href => "google", :tags => ['decent'])

    # Amazon products
    @android = Product.create(:name => 'android', :href => "amazon", :tags => ['awesome'])
    @samsung = Product.create(:name => 'samsung', :href => "amazon", :tags => ['decent'])
    @motorola = Product.create(:name => 'motorola', :href => "amazon", :tags => ['decent'],
      :description => "Not sure about features since I've never owned one.")

    # Ebay products
    @palmpre = Product.create(:name => 'palmpre', :href => "ebay", :tags => ['discontinued', 'worst phone ever'])
    @palm_pixi_plus = Product.create(:name => 'palm pixi plus', :href => "ebay", :tags => ['terrible'])
    @lg_vortex = Product.create(:name => 'lg vortex', :href => "ebay", :tags => ['decent'])
    @t_mobile = Product.create(:name => 't mobile', :href => "ebay", :tags => ['terrible'])

    # Yahoo products
    @htc = Product.create(:name => 'htc', :href => "yahoo", :tags => ['decent'])
    @htc_evo = Product.create(:name => 'htc evo', :href => "yahoo", :tags => ['decent'])
    @ericson = Product.create(:name => 'ericson', :href => "yahoo", :tags => ['decent'])

    # Apple products
    @iphone = Product.create(:name => 'iphone', :href => "apple", :tags => ['awesome', 'poor reception'], 
      :description => 'Puts even more features at your fingertips')

    @products_in_database = Product.all

    Product.tanker_reindex
  end

  describe 'basic searching' do

    it 'should find all amazon products' do
      results = Product.search_tank('amazon')
      results.should include(@android, @samsung, @motorola)
      results.should have_exactly(3).products
    end

    it 'should find the iphone' do
      results = Product.search_tank('iphone')
      results.should include(@iphone)
      results.should have_exactly(1).product
    end

    it 'should find all "palm" phones with wildcard word search' do
      results = Product.search_tank('palm*')
      results.should include(@palmpre, @palm_pixi_plus)
      results.should have_exactly(2).products
    end

    it 'should search multiple words from the same field' do
      results = Product.search_tank('palm pixi plus')
      results.should include(@palm_pixi_plus)
      results.should have_exactly(1).product
    end

    it "should narrow the results by searching across multiple fields" do
      results = Product.search_tank('apple iphone')
      results.should include(@iphone)
      results.should have(1).product
    end

    it "should serach case insensitively" do
      results = Product.search_tank('IPHONE')
      results.should include(@iphone)
      results.should have(1).product
    end
  end

  describe 'searching by tag' do
    it 'should find all "awesome" products regardless of other attributes' do
      results = Product.search_tank('', :conditions => {:tags => 'awesome'})
      results.should include(@android, @iphone)
      results.should have_exactly(2).products
    end

    it 'should find all "decent" products sold by amazon' do
      results = Product.search_tank('amazon', :conditions => {:tags => 'decent'})
      results.should include(@samsung, @motorola)
      results.should have_exactly(2).products
    end

    it 'should find all "terrible" or "discontinued" products sold by ebay' do
      results = Product.search_tank('ebay', :conditions => {:tags => 'terrible OR discontinued'})
      results.should include(@t_mobile, @palmpre, @palm_pixi_plus)
      results.should have_exactly(3).products
    end

    it 'should find products tagged as "discontinued" and "worst phone ever" sold by ebay' do
      results = Product.search_tank('ebay', :conditions => {:tags => ['discontinued', 'worst phone ever']})
      results.should include(@palmpre)
      results.should have_exactly(1).product
    end
  end

  describe "negative search conditions" do

    it 'should find all "awesome" products excluding those sold by apple' do
      results = Product.search_tank('awesome', :conditions => {'-href' => 'apple'})
      results.should include(@android)
      results.should have_exactly(1).product
    end

    it 'should find all "awesome" products excluding those sold by apple (using alternate syntax)' do
      results = Product.search_tank('awesome', :conditions => {'NOT href' => 'apple'})
      results.should include(@android)
      results.should have_exactly(1).product
    end

    it 'should find all "decent" products excluding those sold by apple (using alternate syntax)' do
      results = Product.search_tank('awesome', :conditions => {'NOT href' => 'apple'})
      results.should include(@android)
      results.should have_exactly(1).product
    end

    it 'should find the "htc" but not the "htc evo"' do
      results = Product.search_tank('htc NOT evo')
      results.should include(@htc)
      results.should have_exactly(1).product
    end
  end

  describe "fetching products (as opposed to searching)" do

    before { @results = Product.search_tank('apple', :fetch => [:name]) }

    it 'should find all "apple" products' do
      @results.should have_exactly(1).product
    end

    it "should set values only for the fetched attributes" do
      @results.first.name.should == 'iphone'
    end

    it "should set any non-fetched attributes to nil" do
      @results.first.href.should be_nil
      @results.first.tags.should be_nil
    end

    it "should build results from the index without touching the database" do
      @products_in_database.should_not include(@results)
    end
  end

  describe "searching snippets" do
    before(:all) { @results = Product.search_tank('features', :snippets => [:description]) }

    it 'should find snippets for any product with "features" in the description' do
      @results.should have_exactly(2).products # motorola and iphone
    end

    it "should build results from the index without touching the database" do
      @products_in_database.should_not include(@results)
    end

    it 'should dynamically create an "<attribute>_snippet" method for each result' do
      @results.each { |r| r.should respond_to(:description_snippet) }
    end

    it 'should return a snippet for iphone' do
      snippets = @results.map(&:description_snippet)
      snippets.should include("Puts even more <b>features</b> at your fingertips")
    end

    it 'should return a snippet for motorola' do
      snippets = @results.map(&:description_snippet)
      snippets.should include("Not sure about <b>features</b> since I've never owned one")
    end
  end

  describe "searching snippets while also fetching specific attributes" do
    before :all do 
      @results = Product.search_tank('features', :snippets => [:description], :fetch => [:name, :href])
      @indexed_iphone = @results.detect { |r| r.name == 'iphone' }
      @indexed_motorola = @results.detect { |r| r.name == 'motorola' }
    end

    it 'should find any product with "features" in the description' do
      @results.should include(@indexed_motorola, @indexed_iphone)
      @results.should have_exactly(2).products
    end

    it "should build results from the index without touching the database" do
      @products_in_database.should_not include(@results)
    end

    it 'should set the "name" attribute for all results' do
      @indexed_motorola.name.should == 'motorola'
      @indexed_iphone.name.should == 'iphone'
    end

    it 'should set the "href" attribute for all results' do
      @indexed_motorola.href.should == 'amazon'
      @indexed_iphone.href.should == 'apple'
    end

    it 'should set the "description_snippet" attribute for all results' do
      @indexed_motorola.description_snippet.should == "Not sure about <b>features</b> since I've never owned one"
      @indexed_iphone.description_snippet.should == "Puts even more <b>features</b> at your fingertips"
    end
  end
  
end

