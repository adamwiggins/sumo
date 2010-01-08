require File.dirname(__FILE__) + '/base'

describe Sumo::Instance do
	it "duplicates an existing instance" do
		original = Sumo::Instance.new(:name => 'test', :ami32 => 'abc')
		dupe = original.duplicate
		dupe.class.should == Sumo::Instance
		dupe.name.should == 'test-copy'
		dupe.ami32.should == 'abc'
	end
end
