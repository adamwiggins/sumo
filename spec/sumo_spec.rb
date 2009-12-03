require File.dirname(__FILE__) + '/base'

require 'fileutils'

describe Sumo do
	before do
	end

	after do
	end

	it "defaults to user ubuntu if none is specified in the config" do
		sumo = Sumo::Instance.new :name => "test"
		sumo.user.should == 'ubuntu'
	end

	it "defaults to user can be overwritten on new" do
		sumo = Sumo::Instance.new :name => "test", :user => "root"
		sumo.user.should == 'root'
  end
end
