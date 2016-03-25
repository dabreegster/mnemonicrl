package PerlRL::Component::Game;

use strict;
use warnings;
use Util;

# Provide a means of packages announcing themselves and what type of object they represent
BEGIN {
  sub register {
    my ($package, $type) = @_;
    no strict "refs";
    *{ "${package}::type" } = sub { $type };
    die "$package redefining $type template!\n" if GAME->{Templates}{$type};
    GAME->{Templates}{$type} = $package;
  }
}

# Load shit
use BDSM::Agent;
use BDSM::Agent::Sprite;
use BDSM::Agent::Blob;
use BDSM::Agent::Animated;
use BDSM::Agent::Spotlight;
use BDSM::Static;
use Game::StdLib::Character;
use Game::StdLib::Character::Player;
use Game::StdLib::Character::Monster;
use Game::StdLib::Character::Monster::Snake;
use Game::StdLib::Character::Guest;
use Game::StdLib::Item;
use Game::StdLib::Item::Equipment;
use Game::StdLib::Item::SingleUse;

# Load game-specific shit, TODO configurable eventually
use Game::Mnemonic::Clock;
use Game::Mnemonic::Ingredient;

# Populates some namespaces with some obnoxious crap
use Game::Mechanics;
use Game::Timing;
use BDSM::Map::Level;

# Make a new object from a template
sub make {
  my ($game, $type, @args) = @_;
  die "No $type template to make!\n" unless my $template = $game->{Templates}{$type};
  return $template->new(@args);
}

# Simulate all of the gamestate, BEFORE and extras? Not by default.
sub fullsim { 0 }

# Hmm? We don't care that something's happening.
sub act_cb {}

# Pull in all of the content they specify
sub content {
  my ($game, $load) = @_;

  my $info = do $load;
  require "content/game/$_.pclass" foreach @{ $info->{Classes} };
  foreach (@{ $info->{Monsters} }) {
    push @{ GAME->{Baddies} }, do $_;
    die $@ if $@; # do doesn't return undef, wtf
  }
  foreach (@{ $info->{Items} }) {
    push @{ GAME->{Stuff} }, do $_;
    die $@ if $@; # do doesn't return undef, wtf
  }

  $game->{OverrideLogin} = $info->{Login} // {};

  $info->{Setup}->() if $game->fullsim;
}

# Aint OUR job.
sub addlvl {
  shift;
  BDSM::Map::Level::addlvl(@_);
}

sub schedule {
  my $game = shift;
  $game->{Timers}->schedule(@_);
}

sub unschedule {
  my $game = shift;
  $game->{Timers}->unschedule(@_);
}

42;
