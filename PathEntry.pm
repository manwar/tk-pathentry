# -*- perl -*-

#
# $Id: PathEntry.pm,v 1.21 2007/05/31 16:27:35 k_wittrock Exp $
# Author: Slaven Rezic
#
# Copyright (C) 2001,2002,2003 Slaven Rezic. All rights reserved.
# This package is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
# Mail: srezic@cpan.org
# WWW:  http://www.sourceforge.net/srezic
#

package Tk::PathEntry;

use strict;
use vars qw($VERSION);
$VERSION = sprintf("%d.%02d", q$Revision: 1.21 $ =~ /(\d+)\.(\d+)/);

use base qw(Tk::Derived Tk::Entry);

Construct Tk::Widget 'PathEntry';

sub ClassInit {
    my($class,$mw) = @_;
    $class->SUPER::ClassInit($mw);

    # <Down>  -  popup the choices window
    $mw->bind($class,"<Down>" => sub {
		  my $w = shift;
		  my $choices_t = $w->Subwidget("ChoicesToplevel");
		  # If the popup list is not displayed, display it if possible
		  $w->_popup_on_key($w->get()) if $choices_t->state eq 'withdrawn';
		  if ($choices_t && $choices_t->state ne 'withdrawn') {
		      my $choices_l = $w->Subwidget("ChoicesLabel");
		      $choices_l->focus();
		      my @sel = $choices_l->curselection;
		      if (!@sel) {
			  $choices_l->selectionSet(0);
		      }
		  }
	      });

    for ("Meta", "Alt") {
	$mw->bind($class,"<$_-BackSpace>" => '_delete_last_path_component');
	$mw->bind($class,"<$_-d>"         => '_delete_next_path_component');
	$mw->bind($class,"<$_-f>"         => '_forward_path_component');
	$mw->bind($class,"<$_-b>"         => '_backward_path_component');
	$mw->bind($class,"<$_-Delete>"    => '_delete_next_path_component');
	$mw->bind($class,"<$_-Right>"     => '_forward_path_component');
	$mw->bind($class,"<$_-Left>"      => '_backward_path_component');
    }
    $mw->bind($class,"<FocusOut>" => sub {
		  my $w = shift;
		  # Don't withdraw the choices listbox if the focus just has been passed to it.
		  return if $w->focusCurrent == $w->Subwidget("ChoicesLabel");
		  $w->Finish;
	      });
    $mw->bind($class,"<Return>" => \&_bind_return);

    $class;
}

# Class binding for <Return>

sub _bind_return {
    my $w = shift;
    $w->Finish;
    $w->_exec_selectcmd;
};

sub Populate {
    my($w, $args) = @_;

    # Set proper encoding for file operations
    if ($Tk::VERSION >= 804 && eval { require Encode; 1 }) {
	my $encoding;
	if    ($^O eq 'MSWin32') {$encoding = 'windows-1252'}
#	elsif ($^O eq '.....')   {$encoding = '.....'}    # add known encodings for other platforms
#	elsif ($^O eq '.....')   {$encoding = '.....'}    # see perldoc perlport for OS names
	else                     {$encoding = 'iso-8859-1'}
	$w->{Encoding} = $encoding;
    }

    my $choices_t = $w->Component("Toplevel" => "ChoicesToplevel");
    $choices_t->overrideredirect(1);
    $choices_t->withdraw;

    my $choices_l = $choices_t->Listbox(
					-border => 0,
					-width => 0,    # use autowidth feature
				       )->pack(-fill => "both",
					       -expand => 1);
    if ($Tk::platform eq 'MSWin32') {
	$choices_l->configure(-border => 1, -relief => 'solid');
    } else {
	$choices_l->configure(-background => 'yellow');
    }
    $w->Advertise("ChoicesLabel" => $choices_l);
    # <Button-1> in the Listbox
    $choices_l->bind("<1>" => sub {
			 my $lb = shift;
			 (my $sel) = $lb->curselection;
			 # Take full path from CurrentChoices array
			 $w->_set_text($w->{CurrentChoices}[$sel]);
			 $w->Finish;
		     });
    # <Return> in the Listbox
    $choices_l->bind("<Return>" => sub {
		 # Transfer the selection to the Entry widget
		 my $lb = shift;
		 my @sel = $lb->curselection;
		 if (@sel) {
		     # Take full path from CurrentChoices array
		     $w->_set_text($w->{CurrentChoices}[$sel[0]]);
		 }
		 $w->Finish;
	     });
    # <Return> in the Entry is now a class binding
    # <Escape> in the Listbox
    $choices_l->bind("<Escape>" => sub {
		 $w->Finish;
	     });
    # <Escape> in the Entry
    $w->bind("<Escape>" => sub {
		 $w->Finish;
		 $w->Callback(-cancelcmd => $w);
	     });
    $w->bind("<FocusIn>" => sub {
		 # If the focus is passed to the entry widget by <Tab> or <Shift-Tab>,
		 # all text in the widget gets selected. This might lateron cause
		 # unintended deletion when pressing a key.
		 $w->selectionClear();
	     });

    if (exists $args->{-vcmd} ||
	exists $args->{-validatecommand} ||
	exists $args->{-validate}) {
	die "-vcmd, -validatecommand or -validate are not allowed with PathEntry";
    }

    $args->{-vcmd} = sub {
	my($pathname) = $_[0];
	my($action)   = $_[4];
	$action -= 7 if $action > 5;   # replace actual by official value
	return 1 if $action == -1; # nothing on forced validation

	# validate directory on input of separator
	if ($action == 1) {
	    my $pos_sep_rx = $w->_pos_sep_rx;
	    my $case_rx = $w->cget(-casesensitive) ? "" : "(?i)";
	    $w->_valid_dir('Path', @_) if $pathname =~ /$case_rx$pos_sep_rx$/;
	}
	$w->_popup_on_key($pathname);

	if ($action == 1 && # only on INSERT
	    $w->{CurrentChoices} && @{$w->{CurrentChoices}} == 1 &&
	    $w->cget(-autocomplete)) {
	    # autocomplete annoys when the user is entering a drive name
	    return 1 if ($^O eq 'MSWin32' && length($pathname) == 1);
	    # XXX the afterIdle is hackish
	    $w->afterIdle(sub { $w->_set_text($w->{CurrentChoices}[0]) });
	    return 0;
	}

	1;
    };
    $args->{-validate} = 'key';

    if (!exists $args->{-textvariable}) {
	my $pathname;
	$args->{-textvariable} = \$pathname;
    }
    # avoid undefined initial pathname
    # needed when the user enters <Return> right at the beginning
    ${$args->{-textvariable}} = '' unless defined ${$args->{-textvariable}};

    # validate directory color
    eval {$w->rgb($args->{-dircolor})} if exists $args->{-dircolor};
    if ($@) {
	(my $msg = $@) =~ s/ at .+/ replaced by "blue"/s;
	$w->afterIdle(sub {$w->Callback(-messagecmd => $w, "Option -dircolor: $msg")});
	$args->{-dircolor} = 'blue';
    }

    $w->ConfigSpecs
	(-initialdir  => ['PASSIVE',  undef, undef, undef],
	 -initialfile => ['PASSIVE',  undef, undef, undef],
	 -separator   => ['PASSIVE',  undef, undef,
			  $^O eq "MSWin32" ? ["\\", "/"] : "/"
			  ],
	 -casesensitive => ['PASSIVE', undef, undef,
			    $^O eq "MSWin32" ? 0 : 1
			    ],
	 -autocomplete => ['PASSIVE'],
	 -isdircmd    => ['CALLBACK', undef, undef, ['_is_dir']],
	 -isdirectorycommand => '-isdircmd',
	 -choicescmd  => ['CALLBACK', undef, undef, ['_get_choices']],
	 -choicescommand     => '-choicescmd',
	 -selectcmd   => ['CALLBACK'],
	 -selectcommand => '-selectcmd',
	 -cancelcmd   => ['CALLBACK'],
	 -cancelcommand => '-cancelcmd',
	 -messagecmd  => ['CALLBACK', undef, undef, ['_show_msg']],
	 -messagecommand => '-messagecmd',
	 -complpath    => ['PASSIVE', undef, undef, '<Tab>'],
	 -path_completion => '-complpath',
	 -height        => [$choices_l, qw/height Height 10/],
	 -dircolor      => ['PASSIVE',  undef, undef, undef],
	);
}

sub ConfigChanged {
    my($w,$args) = @_;

    _bind_completion(@_);   # Bind the user-defined completion key
    $w->{max_show} = $w->cget(-height);   # save original height of the listbox
    for (qw/dir file/) {
	if (defined $args->{'-initial' . $_}) {
	    $w->_set_text($args->{'-initial' . $_});
	}
    }
    # validate initial directory
    $w->_valid_dir('Initial directory', $args->{'-initialdir'})
	if (defined $args->{'-initialdir'}  &&  ! defined $args->{'-initialfile'});
}

sub Finish {
    my $w = shift;
    my $choices_t = $w->Subwidget("ChoicesToplevel");
    $choices_t->withdraw;
    $choices_t->idletasks;
    delete $w->{CurrentChoices};
    $w->toplevel->deiconify();   # ensure the visiblity of the container window
    $w->toplevel->raise();
    $w->focus();   # pass focus back to the Entry widget (required for Linux)
}

sub _popup_on_key {
    my($w, $pathname) = @_;
    if ($w->ismapped) {
	if ($w->{Encoding}) {
	    $pathname = Encode::encode("$w->{Encoding}", $pathname);
	}
	$w->{CurrentChoices} = $w->Callback(-choicescmd => $w, $pathname);
	if ($w->{CurrentChoices} && @{$w->{CurrentChoices}} > 1) {
	    my $choices_l = $w->Subwidget("ChoicesLabel");
	    $choices_l->delete(0, 'end');
	    $w->_insert_pathnames($choices_l);
	    # Mark directories if requested
	    $w->_dircolor($choices_l, $w->cget(-dircolor)) if defined $w->cget(-dircolor);
	    # When the focus is passed to the Listbox, the last entry is
	    # active, because the lines were inserted as a list. So pressing
	    # the down arrow would select the last entry.
	    $choices_l->activate(0);
	    $w->_show_choices($w->rootx);
	} else {
	    my $choices_t = $w->Subwidget("ChoicesToplevel");
	    $choices_t->withdraw;
	}
    }
}

sub _sep {
    my $w = shift;
    my $sep = $w->cget(-separator);
    if (ref $sep eq 'ARRAY') {
	$sep->[0];
    } else {
	$sep;
    }

}

sub _pos_sep_rx {
    my $w = shift;
    my $sep = $w->cget(-separator);
    if (ref $sep eq 'ARRAY') {
	"[" . join("", map { quotemeta } @$sep) . "]";
    } else {
	quotemeta $sep;
    }
}

sub _neg_sep_rx {
    my $w = shift;
    my $sep = $w->cget(-separator);
    if (ref $sep eq 'ARRAY') {
	"[^" . join("", map { quotemeta } @$sep) . "]";
    } else {
	"[^" . quotemeta($sep) . "]";
    }
}

sub _delete_last_path_component {
    my $w = shift;

    my $before_cursor = substr($w->get, 0, $w->index("insert"));
    my $after_cursor = substr($w->get, $w->index("insert"));
    my $pos_sep = $w->_pos_sep_rx;
    my $neg_sep = $w->_neg_sep_rx;
    $before_cursor =~ s|$neg_sep+$pos_sep?$||;
    my $pathref = $w->cget(-textvariable);
    $$pathref = $before_cursor . $after_cursor;
    $w->icursor(length $before_cursor);
    $w->_popup_on_key($$pathref);
}

sub _delete_next_path_component {
    my $w = shift;

    my $before_cursor = substr($w->get, 0, $w->index("insert"));
    my $after_cursor = substr($w->get, $w->index("insert"));
    my $pos_sep = $w->_pos_sep_rx;
    my $neg_sep = $w->_neg_sep_rx;
    $after_cursor =~ s|^$pos_sep?$neg_sep+||;
    my $pathref = $w->cget(-textvariable);
    $$pathref = $before_cursor . $after_cursor;
    $w->icursor(length $before_cursor);
    $w->_popup_on_key($$pathref);
}

sub _forward_path_component {
    my $w = shift;
    my $after_cursor = substr($w->get, $w->index("insert"));
    my $pos_sep = $w->_pos_sep_rx;
    my $neg_sep = $w->_neg_sep_rx;
    if ($after_cursor =~ m|^($pos_sep?$neg_sep+)|) {
	$w->icursor($w->index("insert") + length $1);
    }
}

sub _backward_path_component {
    my $w = shift;
    my $before_cursor = substr($w->get, 0, $w->index("insert"));
    my $pos_sep = $w->_pos_sep_rx;
    my $neg_sep = $w->_neg_sep_rx;
    if ($before_cursor =~ m|($neg_sep+$pos_sep?)$|) {
	$w->icursor($w->index("insert") - length $1);
    }
}

sub _common_match {
    my $w = shift;
    my $choices = $w->{CurrentChoices};
    my $case_sensitive = $w->cget(-casesensitive);
    my $common = $choices->[0];
    $common = lc $common if !$case_sensitive;
    foreach my $j (1 .. $#{$choices}) {
	my $choice = $case_sensitive ? $choices->[$j] : lc $choices->[$j];
	if (length $choice < length $common) {
	    substr($common, length $choice) = '';
	}
	for my $i (0 .. length($common) - 1) {
	    if (substr($choice, $i, 1) ne substr($common, $i, 1)) {
		return "" if $i == 0;
		$common = substr($choice, 0, $i);
		last;
	    }
	}
    }
    # Restore original case
    $common = substr($choices->[0], 0, length($common)) if !$case_sensitive;
    $common;
}

sub _get_choices {
    my($w, $pathname) = @_;
    my $neg_sep = $w->_neg_sep_rx;
    if ($pathname =~ m|^~($neg_sep+)$|) {
	my $userglob = $1;
	my @users;
	my $sep = $w->_sep;
	while(my $user = getpwent) {
	    if ($user =~ /^$userglob/) {
		push @users, "~$user$sep";
		last if $#users > 50; # XXX make better optimization!
	    }
	}
	endpwent;
	if (@users) {
	    \@users;
	} else {
	    [$pathname];
	}
    } else {
	my $glob;
	$glob = "$pathname*";
	use File::Glob ':glob';   # allow whitespace in $pathname
	[ glob($glob) ];
    }
}

sub _show_choices {
    my($w, $x_pos) = @_;
    my $choices_t = $w->Subwidget("ChoicesToplevel");

    # Set dynamic height of listbox
    my $choices_height = $w->{max_show};
    if ($choices_height < 0) {
	my $max_height = @{$w->{CurrentChoices}};
	if ($max_height > -$choices_height) {
	    $max_height = -$choices_height;
	}
	my $choices_l = $w->Subwidget("ChoicesLabel");
	$choices_l->configure(-height => $max_height);
    }

    if (defined $x_pos) {
	$choices_t->geometry("+" . $x_pos . "+" . ($w->rooty+$w->height));
	$choices_t->deiconify;
	$choices_t->raise;
    }
}

sub _is_dir { -d $_[1] }

# Bind the user-defined completion key

sub _bind_completion {
    my($w,$args) = @_;

    if ($Tk::platform eq 'MSWin32'  and  $args->{-complpath} eq '<Alt-Tab>') {
	my $msg = 'Event "Alt-Tab" is reserved by the Operating System; use "Tab" instead.';
	$w->Callback(-messagecmd => $w, "Option -path_completion: $msg");
	$args->{-complpath} = '<Tab>';
    }
    eval {$w->bind($args->{-complpath} => \&_complete_current_path)};
    if ($@) {
	(my $msg = $@) =~ s/ at .+/; use "Tab" instead./s;   # cut off line info
	$w->Callback(-messagecmd => $w, "Option -path_completion: $msg");
	$args->{-complpath} = '<Tab>';
	$w->bind('<Tab>' => \&_complete_current_path);
    }
    # Restore standard behaviour of Shift-Tab
    if ($args->{-complpath} eq '<Tab>') {
	$w->bind('<Shift-Tab>' => sub {$w->focusPrev});
    }
}

# Callback to force the completion of the current path

sub _complete_current_path {
    my $w = shift;

    if (!defined $w->{CurrentChoices}) {
	# this is called only on init:
	my $pathref = $w->cget(-textvariable);
	my $pathname = $$pathref;
	if ($w->{Encoding}) {
	    $pathname = Encode::encode("$w->{Encoding}", $pathname);
	}
	$w->{CurrentChoices} = $w->Callback(-choicescmd => $w, $pathname);
    }
    if (@{$w->{CurrentChoices}} > 0) {
	my $pos_sep_rx = $w->_pos_sep_rx;
	my $common = $w->_common_match;
	my $case_rx = $w->cget(-casesensitive) ? "" : "(?i)";
	if ($w->Callback(-isdircmd => $w, $common) &&
	    $common !~ m/$case_rx$pos_sep_rx$/             &&
	    @{$w->{CurrentChoices}} == 1
	   ) {
	    my $sep = $w->_sep;
	    $common .= $sep;
	}
	$w->_set_text($common);
	$w->_popup_on_key($common);
    } else {
	$w->bell;
    }
    Tk->break;
}

# Execute the -selectcmd callback
# pass encoded path as 2nd parameter

sub _exec_selectcmd {
    my $w = shift;

    my $pathname = $ {$w->cget(-textvariable)};
    if ($w->{Encoding}) {
	$pathname = Encode::encode("$w->{Encoding}", $pathname);
    }
    $w->Callback(-selectcmd => $w, $pathname);
}

# Replace text in widget and position the cursor to the end

sub _set_text {
    my ($w, $text) = @_;

    $ {$w->cget(-textvariable)} = $text;
    $w->icursor("end");
    $w->xview("end");
}

# Warn if "directory" exists as a plain file

sub _valid_dir {
    my ($w, $type, $pathname) = @_;

    # remove trailing separators
    my $pos_sep_rx = $w->_pos_sep_rx;
    my $case_rx = $w->cget(-casesensitive) ? "" : "(?i)";
    $pathname =~ s/$case_rx$pos_sep_rx+$//;
    return unless $pathname;
    if (-e $pathname  &&  ! $w->Callback(-isdircmd => $w, $pathname)) {
	# $type is 'Path' or 'Initial directory'.
	$w->Callback(-messagecmd => $w, "$type $pathname\nis not a directory");
        # Don't suppress or attempt to autocorrect the directory.
        # Give the user the chance to correct a typo error.
    }
}

# Insert last component of path names into listbox

sub _insert_pathnames {
    my ($w, $choices_l) = @_;
    my $choices = $w->{CurrentChoices};

    # Show last component of file names
    my $pos_sep_rx = $w->_pos_sep_rx;
    my $case_rx = $w->cget(-casesensitive) ? "" : "(?i)";
    if (@{$choices}[0] =~ /(.*$case_rx$pos_sep_rx)./) {
	my $first = length($1);
	$choices_l->insert("end",
	    map {substr($_, $first)} @{$choices});
    } else {
	$choices_l->insert("end", @{$choices});
    }
}

# Display directories in a different color

sub _dircolor {
    my ($w, $choices_l, $dircolor) = @_;
    my $path;

    foreach (0 .. $choices_l->size - 1) {
	# Take full path from CurrentChoices array
	$path = $w->{CurrentChoices}[$_];
	$choices_l->itemconfigure($_, -foreground => $dircolor)
	    if $w->Callback(-isdircmd => $w, $path);
    }
}

# Show message by default in messageBox

sub _show_msg {
    my ($w, $msg) = @_;

    $w->messageBox(-title => $msg =~ /^Error:/ ? 'Error' : 'Warning',
	-icon => 'warning', -message => $msg);
}

1;

__END__

=head1 NAME

Tk::PathEntry - Entry widget for selecting paths with completion

=head1 SYNOPSIS

    use Tk::PathEntry;
    my $pe = $mw->PathEntry
                     (-textvariable => \$path,
		      -selectcmd => sub { warn "The pathname is $path\n" },
		     )->pack;

=head1 DESCRIPTION

This is an alternative to classic file selection dialogs. It works
more like the file completion in modern shells like C<tcsh> or
C<bash>.

With the C<Tab> key, you can force the completion of the current path.
If there are more choices, a window is popping up with these choices.
With the C<Meta-Backspace> or C<Alt-Backspace> key, the last path
component will be deleted.

=head1 OPTIONS

B<Tk::PathEntry> supports all standard L<Tk::Entry|Tk::Entry> options
except C<-vcmd> and C<-validate> (these are used internally in
B<PathEntry>). The additional options are:

=over 4

=item -initialdir

Set the initial path to the value. Alias: C<-initialfile>. You can
also use a pre-filled C<-textvariable> to set the initial path.

=item -separator

The character used as the path component separator. This may be also
an array reference for multiple characters. For Windows, this is by
default the characters C</> and C<\>, otherwise just C</>.

=item -casesensitive

Set to a true value if the filesystem is case sensitive. For Windows,
this is by default false, otherwise true.

=item -autocomplete

If this is set to a C<true> value, and there remains only one item in the
choices listbox, it will be transferred to the Entry widget automatically.

=item -isdircmd

Can be used to set another directory recognizing subroutine. Alias:
C<-isdirectorycommand>. The directory name is passed as second parameter.
The default is a subroutine using C<-d>.

=item -choicescmd

Can be used to set another globbing subroutine. Alias: C<-choicescommand>. 
The current pathname is passed as second parameter. The
default is a subroutine using the standard C<glob> function.

=item -selectcmd

This will be called if a path is selected by hitting the
Return key in the Entry widget. Alias: C<-selectcommand>.
The encoded path name is passed as second parameter, ready for use in
file operations. You may access the path name as a utf8-string via your 
C<-textvariable> or with C<< $pe->get() >>.

=item -cancelcmd

This will be called if the Escape key is pressed in the Entry widget. Alias:
C<-cancelcommand>.

=item -messagecmd

Can be used to set a different subroutine for displaying messages. 
Alias: C<-messagecommand>. The
message is passed as the second parameter. Examples are 
C<< -messagecmd => sub {print "$_[1]\n"} >>, C<< -messagecmd => sub {$_[0]->bell} >>,
or even C<< -messagecmd => undef >>. The default is a subroutine using
C<messageBox>. 

=item -complpath

This defines the event that will force the completion of the current path. Alias: C<-path_completion>.
By default the C<Tab> key will be used. B<Note>: This default conflicts with the standard use
of the C<Tab> key to move the focus to the next widget.

=item -height

This sets the height of the choices listbox. The default is 10 lines. If height 
is negative, the displayed height changes
dynamically, and the absolute value gives the maximum displayed height.
If height is zero, there is no maximum.

=item -dircolor

This defines the color for marking directories in the choices listbox. By default 
directories are not marked.

=back

=head1 METHODS

=over 4

=item Finish

This will popdown the window with the completion choices. It is called
automatically if the user selects an entry from the listbox, hits the
Return or Escape key or the widget loses the focus.

=back

=head1 ADVERTISED SUBWIDGETS

See L<Tk::mega/"Subwidget"> how to use advertised widgets.

=over 4

=item ChoicesLabel

The Listbox widget that holds the completion choices.

=item ChoicesToplevel

The Toplevel widget for the completion choices.

=back


=head1 BINDINGS

=head2 Bindings of the Entry widget

The B<PathEntry> widget has the same bindings as the L<Entry|Tk::Entry> widget,
exept for C<FocusOut>, which is used internally.
In addition there are the following bindings:

=over 4

=item Down_arrow

Pops up the window with the completion choices and transfers the focus to it.

=item Return

Calls C<Finish> and invokes the C<-selectcmd> callback.

=item Escape

Calls C<Finish> and invokes the C<-cancelcmd> callback.

=item Alt-Backspace I<or> Meta-Backspace

Deletes the path component to the left of the cursor.

=item Alt-d I<or> Meta-d I<or> Alt-Delete I<or> Meta-Delete

Deletes the path component to the right of the cursor.

=item Alt-f I<or> Meta-f I<or> Alt-Right_arrow I<or> Meta-Right_arrow

Moves the cursor one path component to the right.

=item Alt-b I<or> Meta-b I<or> Alt-Left_arrow I<or> Meta-Left_arrow

Moves the cursor one path component to the left.

=back

There is also a user-defined binding, see option C<-complpath>.

=head2 Bindings of the Listbox widget

The choices listbox of the B<PathEntry> widget uses all bindings of 
the L<Listbox|Tk::Listbox> widget.
In addition there are the following bindings:

=over 4

=item Return

Transfers the selected choice to the Entry widget and calls C<Finish>.

=item Escape

Calls C<Finish>.

=item Button-1

Transfers the clicked choice to the Entry widget and calls C<Finish>.

=back

=head1 EXAMPLES

    use Tk::PathEntry;
    my $pe = $mw->PathEntry
        (-autocomplete => 1,
	 -path_completion => '<F5>',
	 -selectcmd => sub {my $f = $_[1]; 
	                    open(OUT, '>', $f) || die "cannot open file $f\n";
                           },
        )->pack(-fill => 'x', -expand => 1);

If you want to not require from your users to install B<Tk::PathEntry>,
you can use the following code snippet to create either a PathEntry or
an Entry, depending on what is installed:


    my $e;
    if (!eval '
        use Tk::PathEntry;
        $e = $mw->PathEntry(-textvariable => \$file,
                            -selectcmd => sub { $e->Finish },
                           );
        1;
    ') {
        $e = $mw->Entry(-textvariable => \$file);
    }
    $e->pack;

=head1 NOTES

Since C<Tk::PathEntry> version 2.17, it is not recommended to bind the
Return key directly. Use the C<-selectcmd> option instead.

=head1 SEE ALSO

L<Tk::PathEntry::Dialog (3)|Tk::PathEntry::Dialog>,
L<Tk::Entry (3)|Tk::Entry>, L<tcsh (1)|tcsh>, L<bash (1)|bash>.

=head1 AUTHOR

Slaven Rezic <srezic@cpan.org>

=head1 COPYRIGHT

Copyright (c) 2001,2002 Slaven Rezic. All rights
reserved. This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

