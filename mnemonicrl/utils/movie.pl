#!/usr/bin/perl

my $fn = shift(@ARGV) // "content/cyphen.map";

use strict;
use warnings;
use lib "../perlrl";
use lib "..";
use Util;

use PerlRL::Component::Game;
use HexedUI::Interface;
use PerlRL::Component::View;
use PerlRL::Component::View::Effects;
use Game::Timing;
use BDSM::Map;
use BDSM::Toy::Conveyor;

package Null;
use Util;
use base "PerlRL::Component::Game";
bless GAME, "Null";
GAME->{NoMapPostProc} = 1;
sub fullsim { 0 }
sub server { 0 }
sub client { 0 }
sub schedule { shift()->{Timers}->schedule(@_); }
sub unschedule { shift()->{Timers}->unschedule(@_); }

package main;

my $map;
my ($start_y, $start_x) = (0, 0);

my $ui = cast HexedUI::Interface {
  FPS    => 1.0 / 30,
  Keymap => "../Keymap",
  Main => {
    Type   => "Map",
    At     => [0, 0],
    Size => ["100%", "100%"],
    #Border => "Green",
    Pad    => 1
  },
};

GAME->{UI} = $ui;

sub open_map {
  my $in = shift;

  # Nuke old effects
  GAME->unschedule(-tags => ["map"]);
  $ui->clean_fx if $map;

  if (ref $in and $in->isa("BDSM::Map")) {
    $map = $in;
  } else {
    $map = bless { Map => [], Agents => {}, Rectangles => {}, Toys => {} }, "BDSM::Map";
    $map->new($in);
  }

  GAME->{Map} = $map;
  $map->{_Data}{superlight} = 0;
  $map->{_Data}{initlight} = 1;



  $ui->{Main}->bindmap($map);
  $ui->{Main}->drawme;

  # Turn on effects
  $ui->eyecandy($_) foreach keys %{ $map->{_Data}{Effects} };

  $map->script("OnLoad") if $map->{Scripts}{OnLoad};
}

my ($offy, $offx) = (-3, -6); # To center the mouse

my ($my, $mx) = (0, 0);
my $light;
$ui->{_Mousehandler} = sub {
  my ($y, $x) = @_;
  return if $y == $my and $x == $mx;
  ($my, $mx) = ($y, $x);

  $y += $ui->{Main}{OffY} + $offy;
  $x += $ui->{Main}{OffX} + $offx;

  if ($light) {
    $light->go($y, $x);
  } else {
    $light = GAME->make("Spotlight",
      Map       => $map,
      At        => [$y, $x],
      Color     => "white",
      #Color     => random_color,
      Size      => "medium",
      no_bounce => 1
    );
  }
};

open_map($fn);
while (1) {
  $ui->{Main}->target(-ref => { Y => $start_y, X => $start_x }, -scroll => 1, -no_quick => 1, -call => sub {
    my (undef, $y, $x, $key) = @_;
    ($start_y, $start_x) = ($y, $x);

    $ui->{Main}->left  if $key eq "h";
    $ui->{Main}->down  if $key eq "j";
    $ui->{Main}->up    if $key eq "k";
    $ui->{Main}->right if $key eq "l";

    if ($key eq " " and $light) {
      #$light->{Color} = random_color;
      $light->{Color} = $light->{Color} eq "white" ? "Red" : "white";
      $light->_blit(1);
    }

    if ($key eq "z") {
      $light->_blit(0);
      BDSM::Agent::Spotlight->circle(
        at => [$light->{Y} - $offy, $light->{X} - $offx]
      );
    }

    #$map->script("Transition") if $key eq "a";

    # Expanding light
    if ($key eq "q") {
      $map->flood(
        -delay => 0.05,
        -from => [[$map->height / 2, $map->width / 2]],
        -dir => "diag",
        -valid => sub { 1 },
        -each_node => sub {
          my ($map, $y, $x) = @_;
          $map->tile($y, $x)->{Lit} = 2;
          $map->modded($y, $x);
        },
        -each_iter => sub {
          $ui->{Main}->drawme;
        }
      );
    }
  });
}
