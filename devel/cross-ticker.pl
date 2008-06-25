#!/usr/bin/perl

# Copyright 2008 Kevin Ryde

# This file is part of Gtk2-Ex-Xor.
#
# Gtk2-Ex-Xor is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation; either version 2, or (at your option) any later
# version.
#
# Gtk2-Ex-Xor is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along
# with Gtk2-Ex-Xor.  If not, see <http://www.gnu.org/licenses/>.


# As of Gtk2::Ex::TickerView version 4, a crosshair on top doesn't display
# properly, because the ticker does XCopyArea to scroll thus shifting around
# the bits crosshair has added.  (But some secret future plans for the
# tickerview might have the happy side-effect of improving that ...)
#


use strict;
use warnings;
use Gtk2 '-init';
use Gtk2::Ex::CrossHair;
use Gtk2::Ex::TickerView;
use Data::Dumper;

# Gtk2::Gdk::Window->set_debug_updates (1);

my $toplevel = Gtk2::Window->new('toplevel');
$toplevel->signal_connect (destroy => sub { Gtk2->main_quit });
$toplevel->set_default_size (300, 0);

my $vbox = Gtk2::VBox->new (0, 0);
$toplevel->add ($vbox);

my $liststore = Gtk2::ListStore->new ('Glib::String');
foreach my $str ('* Item one',
                 '* Item two',
                 '* Item three',
                 '* Item four',
                 '* Item five') {
  $liststore->set_value ($liststore->append, 0 => $str);
}

my $ticker = Gtk2::Ex::TickerView->new (model => $liststore);
my $cellrenderer = Gtk2::CellRendererText->new;
$ticker->pack_start ($cellrenderer, 0);
$ticker->add_attribute ($cellrenderer, text => 0);
$vbox->pack_start ($ticker, 1,1,0);

my $cross = Gtk2::Ex::CrossHair->new (widgets => [ $ticker ],
                                      foreground => 'orange',
                                     );
$ticker->add_events (['button-press-mask','key-press-mask']);
$ticker->signal_connect (button_press_event =>
                        sub {
                          my ($widget, $event) = @_;
                          if ($event->button == 3) {
                            print __FILE__.": start button $widget\n";
                            $cross->start ($event);
                          }
                          return 0; # propagate
                        });
$ticker->signal_connect
  (key_press_event =>
   sub {
     my ($widget, $event) = @_;
     if ($event->keyval == Gtk2::Gdk->keyval_from_name('c')) {
       print __FILE__.": start key $widget\n";
       $cross->start ($event);
       return 1; # don't propagate
     } elsif ($event->keyval == Gtk2::Gdk->keyval_from_name('e')) {
       my ($width, $height) = $ticker->window->get_size;
       print __FILE__.": queue draw top left quarter\n";
       $ticker->queue_draw_area (0,0, $width/2, $height/2);
       return 1; # don't propagate
     } else {
       return 0; # propagate
     }
   });

$toplevel->show_all;
Gtk2->main;
exit 0;
