require File.dirname(__FILE__) + '/base'

describe Sumo do
	it "defaults to user ubuntu if none is specified in the config" do
		sumo = Sumo::Instance.new :name => "test"
		sumo.user.should == 'ubuntu'
	end

	it "defaults to user can be overwritten on new" do
		sumo = Sumo::Instance.new :name => "test", :user => "root"
		sumo.user.should == 'root'
	end
end
