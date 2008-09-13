#!/usr/bin/perl

# Copyright 2008 Kevin Ryde

# This file is part of Gtk2-Ex-Xor.
#
# Gtk2-Ex-Xor is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation; either version 3, or (at your option) any later
# version.
#
# Gtk2-Ex-Xor is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along
# with Gtk2-Ex-Xor.  If not, see <http://www.gnu.org/licenses/>.


# Usage: perl cross-screenshot.pl [outputfile.png]
#
# Draw a sample crosshair and write it to the given output file in PNG
# format.  The default output file is /tmp/cross-screenshot.png.

use strict;
use warnings;
use Gtk2 '-init';
use Gtk2::Ex::CrossHair;
use Gtk2::Ex::Lasso;

use File::Basename;
my $progname = basename($0);

my $output_filename = (@ARGV >= 1 ? $ARGV[0]
                       : '/tmp/cross-screenshot.png');

my $toplevel = Gtk2::Window->new('toplevel');
$toplevel->signal_connect (destroy => sub { Gtk2->main_quit });

$toplevel->set_size_request (200, 100);
$toplevel->modify_bg ('normal', Gtk2::Gdk::Color->parse ('black'));

my $cross = Gtk2::Ex::CrossHair->new (widget => $toplevel,
                                      foreground => 'orange',
                                      line_width => 0);

$toplevel->signal_connect
  (map_event => sub {
     Gtk2::Ex::Lasso::_widget_warp_pointer ($toplevel, 125, 40);
     $cross->start ();

     my $window = $toplevel->window;
     my ($width, $height) = $window->get_size;
     my $pixbuf = Gtk2::Gdk::Pixbuf->get_from_drawable ($window,
                                                        undef, # colormap
                                                        0,0, 0,0,
                                                        $width, $height);
     $pixbuf->save ($output_filename, 'png',
                    'tEXt::Title' => 'CrossHair Screenshot',
                    'tEXt::Author' => 'Kevin Ryde',
                    'tEXt::Copyright' => 'Copyright 2008 Kevin Ryde',
                    'tEXt::Description'
                    => "A sample screenshot of a Gtk2::Ex::CrossHair display.
Generated by $progname");
     Gtk2->main_quit;
   });

$toplevel->show_all;
Gtk2->main;
exit 0
