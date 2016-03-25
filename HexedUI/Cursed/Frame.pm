package HexedUI::Cursed::Frame;

use strict;
use warnings;
use HexedUI::Util;

# We merely extend the HexedUI singleton with more methods. These handle slightly
# higher-level window stuff.

use HexedUI::Hexed::Map;
use HexedUI::Hexed::Menu;
use HexedUI::Hexed::Msg;
use HexedUI::Hexed::Prompt;
use HexedUI::Hexed::Form;

use PUtil::Queue;

# Construct a window.
sub _make_win {
  my ($self, $name, $dat) = @_;

  # Remember ourselves in Layout unless we're resizing.
  unless ($self->{$name}) {
    $self->{_Layout}{$name} = { %$dat }; # Copy the data
  }

  # Size *does* matter!
  my ($rows, $cols) = (@{ $self->{_MaxDims} });
  
  # Any time a size or position says a percent, change that to whatever percent of either
  # the actual rows or columns of our terminal is.
  # Likewise, handle centering
  my @size = @{ $dat->{Size} };
  my @at = @{ $dat->{At} };
  $size[0] =~ s#(\d+)%#$1 * $rows / 100#;
  $size[1] =~ s#(\d+)%#$1 * $cols / 100#;
  $at[0] =~ s#(\d+)%#$1 * $rows / 100#;
  $at[1] =~ s#(\d+)%#$1 * $cols / 100#;
  $at[0] =~ s#center#center(int($size[0]), $rows)#;
  $at[1] =~ s#center#center(int($size[1]), $cols)#;
  
  # And evaluate that value.
  my $sizeY = int eval($size[0]);
  my $sizeX = int eval($size[1]);
  my $posY = int eval($at[0]);
  my $posX = int eval($at[1]);
  delete $dat->{At};
  delete $dat->{Size};
  
  my $win = newwin($sizeY, $sizeX, $posY, $posX);                 
  unless ($win) {
    die "couldnt make win... $sizeY, $sizeX, $posY, $posX\n";
  }

  # If there's a border, then there's automatically an X and Y offset of 1
  # each side. So we lose 2 rows and 2 columns. Reflect that visually.
  # Additionally, the window itself may have more padding.
  my $off = 0;
  $off = 2 if $dat->{Border};
  $off += 2 if $dat->{Pad};

  my $handler = "HexedUI::Hexed::$dat->{Type}";
  my %dat = (
    Name     => $name,
    Win      => $win,
    _HexedUI => $self,
    # These are the coordinates of what we're actually allowed to draw in.
    Y1       => ($off / 2),
    X1       => ($off / 2),
    Height   => $sizeY - $off,
    Width    => $sizeX - $off,
    Border   => $dat->{Border},
    Off      => $off,
    AbsPosY  => $posY,
    AbsPosX  => $posX,
    Opts     => $dat
  );
  $dat{Y2} = $dat{Y1} + $dat{Height};
  $dat{X2} = $dat{X1} + $dat{Width};
  delete $dat->{Border};
  delete $dat->{Pad};
  delete $dat->{Type};

  if (my $win = $self->{$name}) {
    # We're resizing this window, it already exists

    # Overwrite with new data
    delete $dat{Opts};
    delete $dat{_HexedUI};
    delete $dat{Border};
    @$win{keys %dat} = values %dat;

    # We lose our cool Z order for temp windows, which is why those're make_win()'d last
    del_panel($win->{Panel});
    $win->{Panel} = new_panel($win->{Win});
    update_panels();
    doupdate();

    $win->on_resize if $win->can("on_resize");
    $win->draw;
    $win->frameit;
  } else {
    $self->{$name} = $handler->init(%dat);
  }
  $self->{$name}->frameit;
  return $self->{$name};
}

# Destroy a window
sub nuke_win {
  my ($self, $name) = @_;
  my $win = $self->{$name};
  del_panel($win->{Panel});
  $win->{Win}->delwin;

  $self->remove_keyhandler($name);

  delete $self->{$name};
  delete $self->{_Layout}{$name};

  update_panels();
  doupdate();
}

# Return a list of windows.
sub windows {
  my $self = shift;
  # All internal data stuff starts with _
  return map { $self->{$_} } grep(!/^_/, keys %$self);
}

# [internal] Draw a temp title window
sub _title {
  my ($self, $title, $above) = @_;
  my $tmp = $self->{_Tmp};
  $self->_make_win("TmpChooseTitle$tmp" => {
    Type    => "Form",
    At      => [$self->{$above}{AbsPosY} - 3, $self->{$above}{AbsPosX}],
    Size    => [3, $self->{$above}{Width} + 2],
    Border  => 1,
    Center  => 1,
    Reverse => 1,
    Entries => [[[Title => $title]]]
  })->update(Title => "");
}

# Create a temporary popup to select an option from a menu.
sub choose {
  my ($self, $opts, $query, @choices) = args @_;
  $opts->{size} ||= [@choices + 2, 2 + longest($query, @choices)];
  $opts->{size}[0] = "80%" if $opts->{size}[0] > $self->{_MaxDims}[0];
  $opts->{size}[1] = "80%" if $opts->{size}[1] > $self->{_MaxDims}[1];
  $opts->{at}   ||= ["center + 3", "center"];
  die "choose() title needs 3 rows, $opts->{at}[0] is too small\n" if $opts->{at}[0] =~ m/^(\d+)$/ and $1 < 3;

  my $choose = PUtil::Queue->new(Queue => [@choices]);
  my $tmp = ++$self->{_Tmp};
  $self->_make_win("TmpChoosePopup$tmp" => {
    Type       => "Menu",
    At         => $opts->{at},
    Size       => $opts->{size},
    Border     => 1,
    Queue      => $choose,
    KeyHandler => sub {
      my ($win, $key) = @_;
      my $ui = $win->ui;
      $ui->{_BlockingInput} = $win->{Queue}->active if $ui->key($key) eq "ok";
      $ui->{_BlockingInput} = ":cancel:" if $ui->key($key) eq "cancel" and $opts->{escapable};
      # TODO: custom keys
    }
  });
  $self->_title($query, "TmpChoosePopup$tmp");

  my $choice = $self->wait_input;

  # Cleanup
  $self->nuke_win("TmpChooseTitle$tmp");
	$self->nuke_win("TmpChoosePopup$tmp");
  $self->{_Tmp}--;
  return if $choice eq ":cancel:";
  return $opts->{idx} ? $choice : $choices[$choice];
}

# Create a temporary popup window to prompt for input.
sub askfor {
  my ($self, $opts, $query) = args @_;
  my $limit = $opts->{limit} // 10; # TODO should always have a limit prolly..
  $opts->{size} ||= [4, 2 + (length($query) > $limit ? length($query) : $limit)];
  $opts->{at}   ||= ["center", "center"];

  my $tmp = ++$self->{_Tmp};
  my $input = $self->_make_win("TmpPrompt$tmp" => {
    Type    => "Prompt",
    At      => $opts->{at},
    Size    => $opts->{size},
    Border  => 1
  })->prompt($query, $limit);

  # Cleanup
	$self->nuke_win("TmpPrompt$tmp");
  $self->{_Tmp}--;
  return $input;
}

# Pop up a scrolling message window and take input.
sub popup {
  my $self = shift;

  my $win = $self->popup_wait(@_);
  $self->install_keyhandler($win, sub {
    my ($window, $key) = @_;
    if ($key eq "<KEY_UP>") {
      $window->scroll_up;
    } elsif ($key eq "<KEY_DOWN>") {
      $window->scroll_down;
    } else {
      $window->ui->{_BlockingInput} = $key;
    }
  });
  my $input = $self->wait_input;

  # Cleanup
	$self->nuke_win($win->{Name});
  $self->{_Tmp}--;
  return $input;
}

# Create a popup message window, but don't destroy it.
# TODO oy, they have to decrement the _Tmp!
sub popup_wait {
  my ($self, $opts, @lines) = args @_;
  cleanlines(@lines);

  # How high if we're 50% wide?
  my @high = map { wrap(int($self->{_MaxDims}[1] / 2), $_) } @lines;
  my $width = "50%";
  if (scalar @high + 2 > $self->{_MaxDims}[0]) {
    # Make it wider so it'll fit
    $width = "100%";
    @high = map { wrap(int($self->{_MaxDims}[1]), $_) } @lines;
  }

  $opts->{size} ||= [scalar @high + 2, $width];
  $opts->{at}   ||= ["center", "center"];

  my $tmp = ++$self->{_Tmp};
  my $win = $self->_make_win("TmpPopup$tmp" => {
    Type    => "Msg",
    At      => $opts->{at},
    Size    => $opts->{size},
    Border  => 1
  });
  $win->add($_) foreach @lines;
  if ($opts->{start} and $opts->{start} eq "bottom") {
    $win->{Offset} = $win->all - $win->{Height};
    $win->{Offset} = 0 if $win->{Offset} < 0;
  } else {
    $win->{Offset} = 0;
  }
  $win->draw;
  return $win;
}

# Handy-dandy color menu
sub pick_color {
  my $self = shift;
  my @colors = (
    "None",
    "<blue>blue",
    "<Blue>bright blue",
    "<red>red",
    "<Red>bright red",
    "<green>green",
    "<Green>bright green",
    "<aqua>aqua/cyan",
    "<Aqua>bright aqua/cyan",
    "<purple>purple",
    "<Purple>bright purple",
    "<orange>orange",
    "<yellow>yellow",
    "<grey>grey",
    "<white>white",
    "<Black>bright black"
  );                                                                  
  my $color = $self->choose("Foreground Color?", @colors);
  return if $color eq "None";
  $color =~ s/<(\w+)>//;
  my $fg = $1;

  # Now a background color
  @colors = (
    "<$fg>None",
    "<$fg/blue>blue",
    "<$fg/red>red",
    "<$fg/green>green",
    "<$fg/cyan>cyan",
    "<$fg/purple>purple",
    "<$fg/yellow>yellow",
    "<$fg/white>white",
    "<$fg/faded>faded black"
  );
  $color = $self->choose("Background Color?", @colors);
  return $fg if $color eq "<$fg>None";
  $color =~ s/\/(\w+)>//;
  return "$fg/$1";
}

42;
