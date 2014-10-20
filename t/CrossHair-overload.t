#!/usr/bin/perl -w

# Copyright 2010 Kevin Ryde

# This file is part of Gtk2-Ex-Xor.
#
# Gtk2-Ex-Xor is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as published
# by the Free Software Foundation; either version 3, or (at your option) any
# later version.
#
# Gtk2-Ex-Xor is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General
# Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with Gtk2-Ex-Xor.  If not, see <http://www.gnu.org/licenses/>.

use strict;
use warnings;
use Test::More;

use lib 't';
use MyTestHelpers;
BEGIN { MyTestHelpers::nowarnings() }

use Gtk2::Ex::CrossHair;

{
  package MyOverloadWidget;
  use Glib::Object::Subclass 'Gtk2::DrawingArea';
  use Carp;
  use overload '+' => \&add, fallback => 1;
  sub add {
    my ($x, $y, $swap) = @_;
    croak "I am not in the adding mood";
  }
}

require Gtk2;
Gtk2->init_check
  or plan skip_all => 'due to no DISPLAY available';

plan tests => 2;

{
  my $widget = MyOverloadWidget->new;
  ok (! eval { my $x = $widget+0; 1 },
      'widget+0 throws error');

  my $toplevel = Gtk2::Window->new;
  $toplevel->add ($widget);
  $toplevel->show_all;

  my $cross = Gtk2::Ex::CrossHair->new (widget => $widget);

  $toplevel->destroy;
  ok (1);
}

exit 0;
