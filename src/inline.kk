/*---------------------------------------------------------------------------
  Copyright 2013 Microsoft Corporation.

  This is free software; you can redistribute it and/or modify it under the
  terms of the Apache License, Version 2.0. A copy of the License can be
  found in the file "license.txt" at the root of this distribution.
---------------------------------------------------------------------------*/

// Defines the context for _inline_ elements.
module inline

import std/dict
import std/string
import std/regex
import std/log
import common
import attributes  // rules
import codeAlign  // codeTable
import hilite  // hilitemode

public alias cells = list<list<(string,attrs)>>

/* --------------------------------------
 The context for inline elements
---------------------------------------- */
public rectype inlineContext {
  // The parse context for inline elements.
  // Contains a dictionary of all define "links", and the current "grammar".
  // If "sanitize" is "True", all (user) html is supressed or escaped.
  InlineContext( grammar    : grammar<string,inlineContext>,
                 links      : dict<link>,
                 labels     : dict<label>,
                 footnotes  : dict<footnote>,
                 defaults   : rules,
                 metadata   : dict<string>,
                 embedinfos : dict<embedinfo>,
                 xsanitize  : bool,
                 bench      : bool,
                 verbose    : int,
                 highlight  : bool,
                 starBold   : bool,
                 sandbox    : bool,
                 prettyAlign : int,

                 xfmtCmd : (ctx:inlineContext,cmd:string,body:string,attrs:attrs) -> string,
                 xfmtEscape : (ctx:inlineContext,body:string,allowEntity:bool) -> string,
                 xfmtLink: (ctx:inlineContext,isImage : bool, link : link, content : string ) -> string,
                 xfmtFootnote: (context : inlineContext, id : string, fn : footnote ) -> console string,
                 xfmtTable: (context : inlineContext, head : list<row>, body : list<row>, colattrs: list<attrs>, attrs : attrs ) -> string,
                 xfmtEnv : (context : inlineContext, env : string, txt : string, attrs : attrs ) -> string,
                 xfmtCodePlain : (context : inlineContext, txt : string, startline : bool ) -> string,
                 // xfmtCodeHilite : (context : inlineContext, txt : string, startLine: bool ) -> (string),
                 xfmtCodeToken : (context : inlineContext, classes: list<string>, txt : string, lang : string, attrs : attrs) -> string,
                 xfmtLineInfo : (context : inlineContext, lineInfo : string ) -> string,
                 xfmtCodeTable : (context : inlineContext, ct : codeTable, attrs : attrs ) -> string,
                 xfmtMathCmd : (ctx:inlineContext,cmd:string,body:string,attrs:attrs) -> string,
                 xfmtMathEnv : (context : inlineContext, env : string, txt : string, attrs : attrs ) -> string,
                 fmt : formatter
               )
}

public struct titleinfo (
  title : string,
  subtitle : string,
  authors : list<authorinfo>,
  note : string
)

public struct authorinfo (
  name : string,
  address : string,
  email : string,
  note : string
)

public rectype footnote {
  Footnote( footnoteNum : string,
            footnoteContent : (inlineContext) -> console string,
            footnoteCaption : string  )
}

public function fmtCmd( context : inlineContext, cmd : string, txt : string, attrs : attrs = attrsNone ) : <console> string {
  (context.xfmtCmd)(context,cmd,txt,attrs)
}

public function fmtEnv( context : inlineContext, env : string, txt : string, attrs : attrs = attrsNone ) : string {
  (context.xfmtEnv)(context,env,txt,attrs)
}

public function fmtMathCmd( context : inlineContext, cmd : string, txt : string, attrs : attrs = attrsNone ) : string {
  (context.xfmtMathCmd)(context,cmd,txt,attrs)
}

public function fmtMathEnv( context : inlineContext, env : string, txt : string, attrs : attrs = attrsNone ) : string {
  (context.xfmtMathEnv)(context,env,txt,attrs)
}

public function fmtCodePlain( context : inlineContext, txt : string, startline : bool = True ) : string {
  (context.xfmtCodePlain)(context,txt,startline)
}

public function fmtCodeToken( context: inlineContext, classes : list<string>, txt : string, lang : string, attrs : attrs ) : string {
  (context.xfmtCodeToken)(context,classes,txt,lang,attrs)
}

public function fmtEscapePre( context : inlineContext, txt : string ) : string {
  (context.xfmtEscape)(context,txt,False)
}

public function fmtEscape( context : inlineContext, txt : string ) : string {
  (context.xfmtEscape)(context,txt,True)
}

public function fmtText( context : inlineContext, txt : string ) : string {
  (context.xfmtCmd)(context,"",txt,attrsNone)
}

public function fmtLink( context : inlineContext, isImage : bool, link : link, content : string) : string {
  (context.xfmtLink)(context,isImage,link,content)
}

public function fmtFootnote(context : inlineContext, id : string, fn : footnote ) : console string {
  (context.xfmtFootnote)(context,id,fn)
}

public function fmtLineInfo(context : inlineContext, lineInfo : string ) : string {
  (context.xfmtLineInfo)(context,lineInfo)
}

public function fmtCodeTable(context : inlineContext, ct : codeTable, attrs : attrs = attrsNone ) : <console> string {
  (context.xfmtCodeTable)(context,ct,attrs)
}

// Copy an ":inlineContext"
public function copy( self : inlineContext,
                       grammar : grammar<string,inlineContext> = self.grammar,
                       links : dict<link> = self.links,
                       labels : dict<label> = self.labels,
                       footnotes : dict<footnote> = self.footnotes,
                       defaults: rules = self.defaults,
                       metadata: dict<string> = self.metadata,
                       embedinfos : dict<embedinfo> = self.embedinfos,
                       sanitize : bool = self.sanitize,
                       bench : bool = self.bench,
                       verbose : int = self.verbose,
                       highlight : bool = self.highlight,
                       starBold : bool = self.starBold,
                       sandbox: bool = self.sandbox,
                       prettyAlign : int = self.prettyAlign,
                       xfmtCmd = self.xfmtCmd,
                       xfmtEscape = self.xfmtEscape,
                       xfmtLink = self.xfmtLink,
                       xfmtFootnote = self.xfmtFootnote,
                       xfmtTable = self.xfmtTable,
                       xfmtEnv = self.xfmtEnv,
                       xfmtCodePlain = self.xfmtCodePlain,
                       //xfmtCodeHilite = self.xfmtCodeHilite,
                       xfmtCodeToken = self.xfmtCodeToken,
                       xfmtLineInfo = self.xfmtLineInfo,
                       xfmtCodeTable = self.xfmtCodeTable,
                       xfmtMathCmd = self.xfmtMathCmd,
                       xfmtMathEnv = self.xfmtMathEnv,
                       fmt : formatter = self.fmt  ) : inlineContext
{
  InlineContext( grammar,links,labels,footnotes,defaults,metadata,embedinfos,
                 sanitize,bench,verbose,highlight,starBold,sandbox,prettyAlign,
                 xfmtCmd,xfmtEscape,xfmtLink,xfmtFootnote,xfmtTable,
                 xfmtEnv, xfmtCodePlain, /* xfmtCodeHilite, */
                 xfmtCodeToken, xfmtLineInfo, xfmtCodeTable,
                 xfmtMathCmd, xfmtMathEnv,
                 fmt )
}

public function sanitize( context : inlineContext ) : bool {
  context.xsanitize
}


/* --------------------------------------
  Parse inline text elements
---------------------------------------- */

public function logDataLine( attrs ) : () {
  match(attrs.hasKey("data-line")) {
    Nothing     -> ()
    Just(line)  -> logLocation(line)
  }
}

// Parse _inline_ markdown elements and return formatted html
public function formatInline( context : inlineContext, txt : string, attrs : attrs = attrsNone ) : <console> string
{
  formatInlineAcc(context,builder(), txt)
}

public function parseLineInfo( lineInfo : string ) : (string,int) {
  match (lineInfo.find(rxDataLine)) {
    Nothing   -> ("",0)
    Just(cap) -> (cap.groups[1],cap.groups[2].parseIntDefault(0))
  }
}
val rxDataLine = regex( @"^(.*:)?(\d+)$")

function formatInlineAcc( context : inlineContext, acc : builder<h>, txt : string) : <st<h>,console> string
{
  if (txt=="") return acc.build
  val (s,next,_) = matchRules(context.grammar,context,txt,id)
  formatInlineAcc(context, acc.append(s), txt.substr1(next))
}



public function mathPreX( txt : string ) : string
{
  val ignorearg = @"(?:mbox|begin|end|(?:text|math|varmath)(?:kw|id|rm|sf|tt|up|it|sl|sc|bf|md|lf|normal|bb|cal|scr|bbm|bbmss|bbmtt|ds|frak|swab|goth)?)"
  txt.replaceAll(regex(@"(\\" + ignorearg + @"{(?:[^\\}]|\\.)*}|\\[a-zA-Z@]+ *|\\[^a-z@])|^( +)|( +)|(\n)",multiline=True), fun(cap) {
        val n = cap.matched.length
        if (cap.groups.matchedOn(2)) then @"\mdmathindent{" + n.show + "}"
        elif (cap.groups.matchedOn(3)) then string(n,'~') // @"\mdMathspace{" + cap.matched.length.show + "}"
        elif (cap.groups.matchedOn(4)) then "\\\\\n" // \\mdMathbr{}\n"
        else cap.matched
      })
     .replaceAll(regex(@"(\\" + ignorearg + @"{(?:[^\\}]|\\.)*}|\\[a-z@]+(?![a-z@]))|#([a-z][a-z\d]*(?![a-z\d]))|([a-z][a-z\d]*(?![a-z\d]))|@([a-z][a-z\d]*(?![a-z\d]))", ignoreCase=True), fun(cap) {
        val grp = cap.groups.firstMatchedOn
        if (grp==2) then cap.groups[2]
        elif (grp < 2) then cap.matched
        else {
          val cmd = if (cap.groups.matchedOn(4)) then "mathkw" else "mathid"
          val captxt = cap.groups[grp]
          val (stem,digits) = match(captxt.find(regex(@"^([^\d]*(?:\d+[^\d]+)*)(\d*)$"))) {
                                Just(ccap) -> (ccap.groups[1],ccap.groups[2])
                                Nothing    -> (captxt,"")
                              }
          "\\" + cmd + "{" + stem + "}" + (if (digits=="") then "" else "_{" + digits + "}")
        }
      })
}

public function mathPre( txt : string ) : string {
  "\\mathpre{" + txt.mathPreX + "}"
}

public function mathPreBlock( txt : string) : string
{
  val pre = mathPreX(txt)
  "\\begin{mdmathpre}%mdk\n" + pre + "\n\\end{mdmathpre}%mdk\n"
}
