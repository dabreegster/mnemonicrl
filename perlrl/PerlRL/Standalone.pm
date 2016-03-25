package PerlRL::Standalone;

use strict;
use warnings;
use Util;

# Particular order >_<
BEGIN {
  bless GAME, __PACKAGE__ if ref GAME eq "HASH";
  our @ISA = ("PerlRL::Component::Game");
}

# TODO tmp
sub server { 0 }
sub client { 0 }
sub fullsim { 1 }

use HexedUI::Interface; # POE bug
use PerlRL::Component::Game;
use PerlRL::Component::View;
use PerlRL::Component::View::Effects;
use PerlRL::Component::View::Actions;
use BDSM::Map;
use Data::Dumper;

# Splashscreen menu
sub init {
  my ($game, $load) = @_;
  $game->{Fillers} = -1;  # So we can keep those IDs separate as well

  $game->content($load);  # Oh, and load the game content. Minor detail ;)

  $game->setup_ui;
  my $ui = $game->{UI};

  my $title = BDSM::Map->new("content/trailer/logo.map");
  my $splash = $ui->_make_win(Titlescreen => {
    Type   => "Map",
    At	   => [0, 0],
    Size   => ["100%", "100%"],
    Border => 1,
    Pad    => 1
  });
  # TODO Everything is gonna want Main :(   Should open a new window set..
  my $main = UI->{Main};
  UI->{Main} = $splash;
  $game->changemap($title);
  $splash->refocus;
  $splash->drawme;

  GAME->{Login} = do "../player.conf" if -f "../player.conf";

  while (1) {
    my $todo = UI->choose(-at => [15, 12], "What to do?" => "Play", "Change Character");
    if ($todo ne "Play" or !GAME->{Login}) {
      my ($name, $symbol, $color, $gender, $class);
      $name = $ui->askfor(-limit => 10, "What's your name?") || "Anonymous";
  
      $symbol = $ui->askfor(-limit => 1, "What's your symbol? (any uppercase or lowercase letter)");
      $symbol = "@" unless $symbol; #=~ m/^[a-zA-Z]$/;

      $color = $ui->pick_color;
      $color ||= "grey";  # Damn they're stubborn

      $gender = $ui->choose("What is your gender?" => "Androgynous", "Male", "Female");

      $class = $ui->choose("What class do you wish to play?" => "Adventurer", "Alchemist",
        "Artist", "Historian", "MadScientist", "Musician", "Steamist", "Villain");

      GAME->{Login} = {
        Name   => $name,
        Symbol => $symbol,
        Color  => $color,
        Gender => $gender,
        Class  => $class,
      };

      open my $save, ">../player.conf" or die "Can't open player.conf to write: $!\n";
      print $save Data::Dumper::Dumper(GAME->{Login});
      close $save;
    }
    if ($todo eq "Play") {
      %{ GAME->{Login} } = (%{ GAME->{Login} }, %{ GAME->{OverrideLogin} });
      GAME->unschedule(-tags => ["map"]);
      UI->{Main} = $main;
      UI->draw_timed($main);  # Heh, gotta tel the redraw loop about the real Main ;)
      GAME->play;
      last;
    }
  }
}

# Just start POE
sub start {
  POE::Kernel->run;
}

# Housekeeping...
sub play {
  my $game = shift;
  UI->install_keyhandler({ Name => "Dummy for Game Keyhandler" } => \&_game_tick);

  UI->popup(
    -size => ["80%", "80%"],
    "Welcome to MnemonicRL!",
    "Use <cyan>tab<grey> to chat, arrow keys or vi keys (hjklyubn) for movement, and
    <cyan><<grey> and <cyan>><grey> to descend/ascend staircases. <red>Press <Cyan>?<red>
    for more help.",
    "",
    "<Green>The Daily Mnemonic Device",
    "",
    @{ CFG->{News} }
  );

  UI->nuke_win("Titlescreen");

  $game->{Countdown} = 0;
  $game->schedule(
    -do => sub {
      return 0.2 unless $game->{Map};  # Wait
      if ($game->{Countdown}) {# or !UI->{Battle}{Entries}{Wait}{Old}) {
        my $cnt = $game->{Countdown} = max(0, $game->{Countdown} - 0.2);
        my $line = $cnt ? sprintf("<black/white>%.1f<grey>", $cnt) : "<Green>GO";
        UI->{Bar}->update(Wait => $line);
      }
      return 0.2;
    },
    -tags => ["ui"],
    -id   => "player_waiter"
  );
  UI->{Bar}->update(Wait => "<Green>GO");

  $game->begin;
}

sub begin {
  my $game = shift;
  # Make our hero, I guess
  my $dat = GAME->{Login};
  my $us = GAME->make(delete $dat->{Class},
    Map        => GAME->{Levels}{Start},
    Level      => 1,
    %$dat
  );
  GAME->{Player} = $us;

  $game->got_player($us);
}

# Load up a new map... does everything but tell it to draw, since everyone wants different
# focus/lighting stuff
sub changemap {
  my ($game, $map) = @_;

  # Nuke old effects
  GAME->unschedule(-tags => ["map"]);
  UI->clean_fx if GAME->{Map};

  GAME->{Map} = $map;
  UI->{Main}->bindmap($map);

  # Turn on effects
  UI->eyecandy($_) foreach keys %{ $map->{_Data}{Effects} };

  # Execute the script, if any
  $map->script("OnLoad") if $map->{Scripts}{OnLoad};
}

# Awww, so silent
sub chat_cb {
  my ($game, $msg) = @_;
  msg chat => $msg;
}

# The default key handler to either chat or do actions
my $focus = "game";
sub _game_tick {
  my (undef, $key) = @_;
  my $game = GAME;
  my $ui = UI;

  my $player = Player;

  if (UI->key($key) eq "switch_focus" or ($focus eq "game" and UI->key($key) eq "ok")) {
    if ($focus eq "game") {
      $focus = "chat";
      $ui->{Main}->frameit("grey");
      $ui->{Msgs}->frameit("green");
      $ui->{Prompt}->frameit("green");
    } else {
      $focus = "game";
      $ui->{Main}->frameit("green");
      $ui->{Msgs}->frameit("grey");
      $ui->{Prompt}->frameit("grey");
    }
  }
  if ($focus eq "chat") {
    if (UI->key($key) eq "ok") {
      my $in = $ui->{Prompt}->stop_prompt;
      $ui->{Prompt}->start_prompt;
      $game->chat_cb($in) if $in;
    } elsif (UI->key($key) eq "up") {
      $ui->{Msgs}->scroll_up;
    } elsif (UI->key($key) eq "down") {
      $ui->{Msgs}->scroll_down;
    } else {
      $ui->{Prompt}->nextkey($key);
    }
    return;
  }

  return unless GAME->{Map} and Player;  # We're in between stuff right now

  my $do = UI->key(Commands => $key);
  if (Player->{Explore}) {
    # Interrupt and stop it
    GAME->unschedule(-tags => ["explore"]);
    delete Player->{Explore};
  }

  return unless $do;

  return if time() < $player->{Lag};
  $player->{Lag} = 0;

  my @args;
  if (ref $do) {
    ($do, @args) = @$do;
  }
  my $heap = {};  # We want it back!
  if ($player->$do(-stages => ["Pre"], -heap => $heap, @args)) {
    $game->goodcmd_cb($player, $heap);
  }
}

# When we win, just... do it.
sub goodcmd_cb {
  my ($game, $player, $heap) = @_;
  my $verb = $heap->{Action};
  $player->$verb(@{ $heap->{Args} });
}

sub dbug_cb {
  my ($game, $err) = @_;
  msg err => $err;
}

# Inject

package Game::StdLib::Character;

sub AFTER_changedepth {
  my ($self, $heap) = actargs @_;
  return unless $self->player;
  GAME->changemap($self->{Map});
  UI->{Main}->light($self);
  UI->{Main}->focus;
  UI->{Main}->drawme;
}

package Game::StdLib::Character::Player;

sub PRE_lswho {
  my $self = shift;
  # TODO err channel plox?
  return STOP($self, "You're playing single-player; nobody's on!");
}

sub human_control {
  my $self = shift;
  return Player and Player->id == $self->id;
}

42;
