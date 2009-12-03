require 'jeweler'

Jeweler::Tasks.new do |s|
	s.name = "sumo"
	s.description = "A no-hassle way to launch one-off EC2 instances from the command line"
	s.summary = s.description
	s.author = "Adam Wiggins"
	s.email = "adam@heroku.com"
	s.homepage = "http://github.com/adamwiggins/sumo"
	s.rubyforge_project = "sumo"
	s.files = FileList["[A-Z]*", "{bin,lib,spec}/**/*"]
	s.executables = %w(sumo)
	s.add_dependency "uuidtools"
	s.add_dependency "aws"
	s.add_dependency "thor"
	s.add_dependency "json"
end

Jeweler::RubyforgeTasks.new

desc 'Run specs'
task :spec do
	sh 'bacon -s spec/*_spec.rb'
end

task :default => :spec

