# Madoko -- a Fast Scholarly Markdown Processor (now optimized for paper processing)

Madoko is a fast javascript [Markdown] processor written in [Koka]
It started out as a demo program for the new, strongly typed, [Koka] language and
the name comes from "_Ma_\/rk\/_do_\/wn in _Ko_\/ka".

**This fork of Madoko is optimized for processing papers (LaTeX only)**
In particular:

- it has to be used from the command line
- no html output is generated
- no svg/png images are generated for math
- local client and webserver have been completely removed
- bibliography is not processed
- original LaTeX commands are used where possible

This significantly speeds up processing for larger documents and simplifies conformance to style requirements imposed by conferences.

## Using Madoko

You can run Madoko on the command line:

* Ensure you have [Node.js](http://nodejs.org) installed on your system.

* At the moment you need to build Madoko yourselves and run `npm link` in the `lib` folder.
  Information on building can be found in the `Jakefile.js`

Translating a markdown document is done simply as:

* `madoko -v mydoc.mdk`

which generates `mydoc.tex`. The `-v` flag gives more verbose output.
To also generate a PDF file, use:

* `madoko -v --odir=out mydoc`

where `--odir` puts all output files in the `out` directory.

## Madoko philosophy

The main design goal of Madoko is to enable light-weight creation of 
high-quality scholarly and industrial documents for the web and print,
while maintaining John Gruber's Markdown philosophy of simplicity and focus on
plain text readability.

The popularity of Markdown is not accidental, and it is great for writing
prose: it is super simple and straightforward to create good looking HTML
documents. But for more serious use Markdown falls short in several areas,
and Madoko provides many essential additions for larger documents.

Besides HTML output, Madoko also generates high-quality PDF files through LaTeX. Even
though more Markdown implementations support this, there has been a lot of
effort in Madoko to make the LaTeX generation robust and customizable. This
makes it possible to write high-quality articles using just Madoko and get
both a high-quality print format (PDF) and a good looking HTML page.

For more information look at the [Madoko manual](http://research.microsoft.com/en-us/um/people/daan/madoko/doc/reference.html)

Have fun,
-- Daan

[Koka]:     http://koka.codeplex.com
[dropbox]:  http://dropbox.com
[github]:   http://github.com
[markdown]: http://daringfireball.net/projects/markdown/
