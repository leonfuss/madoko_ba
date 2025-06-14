/*---------------------------------------------------------------------------
  Copyright 2013 Microsoft Corporation.

  This is free software; you can redistribute it and/or modify it under the
  terms of the Apache License, Version 2.0. A copy of the License can be
  found in the file "license.txt" at the root of this distribution.
---------------------------------------------------------------------------*/

// The parsing and formatting of _inline_ elements (i.e. emphasis, links, etc.)
module formatInline

import std/log
import std/dict
import std/string
import std/regex
import std/crypto
import std/path   // extname
import common
import attributes
import inline
import latexFormatter
import entity
import hilite // inlineMode
import codeAlign

/* --------------------------------------
  Inline grammar
---------------------------------------- */
alias inlineRule = rule<string,inlineContext>

val normal       = @"(?:[^`*_\\~&<>\^#\$""'\[!\-\. \+@]| (?! \n| *[\[\-\+!@])|-(?![@\-])|\+(?!@)|\.(?!\.\.)|!(?![@\[]))"
val normalbench  = @"(?:[^""'`*_\\~&<>\^#\$\[!]| (?! \n))"

//val attrs    = @"\{:?((?:[^\}\n]|\\\})*)\}"
val attrs      = @"\{:?((?:[^\\'""\}\n]|\\[.\n]|'[^']*'|""[^""]*"")*)\}"  // allow optional colon for maraku compat

val linkhref = @"\s*<?([^\s>)]*)>?(?:\s+['""](.*?)['""])?\s*"
val xlinkid   = @"((?:[^\[\]\n]|\[[^\]\n]*\])*)"
val linktxt  = @"\[(?!\^)((?:\[(?:[^\[\]]|\[(?:[^\[\]]|\[[^\]]*\])*\])*\]|\\.|[^\\\]]|\](?=[^\[{]*\]))*)\]"
val linkreg  = linktxt + @"((?:\(" + linkhref + @"\)|\s*\[" + xlinkid + @"\])?(?:" + attrs + @")?)"

public val rxLink = regex(linkreg)

function inlineCoreGrammar( fmt : formatter ) : grammar<string,inlineContext> = [
  Rule("itext",     regex(@"^" + normal + "+"), inlineNormal ),

  Rule("iquotes",   regex(@"^(?:'(?!\s|s\b|re\b)((?:[^\\'`\$\[<]|\\.|'[a-zA-Z])*)'(?![a-zA-Z])|""((?:[^\\""`\$\[<]|\\.)*)"")"), inlineQuotes ),
  Rule("icode",     regex(@"^(`+)((?:[^`]|(?!\1)`)*)\1(?:" + attrs + ")?"), inlineCode ),
  Rule("ilink",     regex(@"^([\n ]*)" + linkreg), inlineLink ),
  Rule("iemph*",    regex(@"^(\*)((?:[^\\*]|\\.)+)\*"), inlineEmph),

  Rule("iimg",      regex(@"^()!" + linkreg), inlineImg ),
  Rule("ifootnote", regex(@"^\[\^" + xlinkid + @"\]"), inlineFootnote ),
  Rule("iguil",     regex(@"^<<((?:[^\\>]|>(?!>)|\\.)*)>>"), inlineQuotes ),
  Rule("iautolink", regex(@"^<([^/\s>][^\s>]*?(@|:/)[^\s>]+?)>(?:" + attrs + ")?"), inlineAutoLink ),
  Rule("istrong_",  regex(@"^(__)((?:[^\\]|\\.)+?)__(?!_)"), inlineStrong),
  Rule("istrong*",  regex(@"^(\*\*)((?:[^\\]|\\.)+?)\*\*(?!\*)"), inlineStrong),
  Rule("iemph_",    regex(@"^\b(_)((?:[^\\_]|\\.)+)_\b"), inlineEmph),
  Rule("idel",      regex(@"^~~(?=\S)([\s\S]*?\S)~~"), inlineDel ),
  Rule("isub",      regex(@"^~((?:[^~\\\n\r]|\\.)+)~"), inlineSub ),
  Rule("isup",      regex(@"^\^((?:[^\^\\\n\r]|\\.)+)\^"), inlineSup ),
  Rule("itagcode",  regex(@"^(<code\b(?:""[^""]*""|'[^']*'|[^'"">])*?>)([\s\S]*?)(</code>)"), inlineTagCode ),
  Rule("itag",      regex(@"^<(?:!--[\s\S]*?-->|/?\w+\b(?:""[^""]*""|'[^']*'|[^'"">])*?>)"), inlineTag ),
  Rule("ientity",   regex(@"^&(#?[\w\-:]*);"), inlineEntity ),
  //Rule("ilabel",    regex(@"^(#[a-zA-Z][\w\-:]*);?"), inlineLabel ),

  Rule("idashes",   regex(@"^--(-)?"), inlineDashes ),
  Rule("ielipsis",  regex(@"^\.\.\."), inlineDots ),

  Rule("texinline", regex(@"^\$(?!\$)((?:[^\\\$]|\\[\s\S])+)\$(?:" + attrs + ")?"), inlineMath ),
  Rule("texblock1", regex(@"^\$\$( *\n(?:[^\\\$]|\\[\s\S]|\$[^\$])*)\$\$"), inlineMathBlock ),
  Rule("texblock2", regex(@"^\\\[( *\n(?:[^\\]|\\[^\]])*)\\\]"), inlineMathBlock ),

  Rule("textcite",  regex(@"^([\n ]*)(([\-+!]?)@" + rxCitename + ")"), inlineCite ),

  Rule("ibr",       regex(@"^  \n(?!\s*$)"), inlineBreak ),
  Rule("iescape",   regex(@"^\\([^a-zA-Z0-9])"), inlineEscape ),

  Rule("other",     regex(@"^[\s\S]"), inlineOther ),
]

val benchGrammar
  = inlineCoreGrammar(FmtHtml).stripFancyRules

function stripFancyRules( g : grammar<string,inlineContext> ) : grammar<string,inlineContext> {
  g.ruleReplace(True, Rule("itext", regex("^" + normalbench + "+"), inlineNormal ))
   .ruleReplace(True, Rule("iquotes", regex(@"^[""']"), inlineQuot ))
   .ruleRemove(True,["idashes","ielipsis","tex","iguil","textcite"])
}

public function inlineGrammar( fmt : formatter, bench : bool = False ) {
  if (bench) then benchGrammar else inlineCoreGrammar(fmt)
}


/* --------------------------------------
 Inline grammar functions
---------------------------------------- */

function inlineBreak( cap : matched, context ) {
  context.fmtCmd("br","")
}

function inlineEntity( cap : matched, context : inlineContext ) : <console> string {
  val key = cap.groups[1]
  if (key.startsWith("#")) // character code
   then context.fmtText(cap.matched)
   else {
    val txt = expandKeyName(key,context.labels,context.metadata)
    if (txt==cap.matched)             // prevent obvious infinite loop
     then context.fmtText(txt)
     else context.formatInline(txt)   // format the expansion
  }
}

function inlineNormal( cap : matched, context : inlineContext ) : string {
  context.fmtText(cap.matched)
}

function inlineMath( cap : matched, context : inlineContext ) : <console> string {
  val attrs = cap.groups[2].parseAttrs("math-inline");
  context.fmtSpan( cap.groups[1], attrs ); // can be taken over by the user
}


function inlineMathBlock( cap : matched, context : inlineContext ) : <console> string {
  val attrsd = context.defaults.matchRules("math-display",attrsNone)
  context.fmtMath(True,cap.groups[1],attrsd)
}

public function fmtMath( context : inlineContext, isDisplay : bool, txt0 : string, attrs : attrs = attrsNone) : <console> string {
  val (kind,left,right,rightx) =
    if (attrs.hasClass("snippet"))
     then (if (isDisplay) then "Display" else "Inline","","","")
    elif (isDisplay)
     then ("Display","\\[" + (if (attrs.name.isEmpty) then "" else "\\label{" + attrs.name + "}"),"\n\\]","%mdk-136\n")  // add newline because of comments in latex (and we do use trimLines on the content)
     else ("Inline","$","$","")
  val lkind  = kind.toLower
  val class  = "math-" + lkind
  val attrsd = context.applyDefaults("span",attrs.addClass(class))

  // This is very dangerous! Trimming lines from potentially generated code
  // might result in
  //   foo%mdk\n -> foo%mdk
  // TODO not sure what it means to NOT trim lines here
  val txt    = txt0.trimLines
  if (kind=="Inline")
    then context.fmtMathCmd("span", left+txt+right+rightx, attrsd)
    else context.fmtMathEnv("div",  left+txt+right+rightx, attrsd)
}

function logMathLocation(digest: string, attrs: attrs) {
  val start = attrs.lookupKey("data-line-start", "")
  val end   = attrs.lookupKey("data-line-end", "")
  if (start == "" || end == "") return ()
  else log("math-locations", start + "," + end + "," + digest)
}

function escapeMath( txt : string, fmt : formatter ) : string {
  txt
}


function inlineQuot( cap : matched, context ) : <console> string {
  context.formatInline(if (cap.matched=="\"") then "&quot;" else "&apos;")
}

function inlineStrong( cap : matched, context ) : <console> string {
  val tag = if (context.starBold && cap.matched.startsWith("_")) then "em" else "strong"
  val class = tag + (if (cap.matched.startsWith("*")) then "-star" else "-low") + cap.groups[1].length.show
  val attrs = context.defaults.matchRules( tag, attrsNone.addClass(class) )
  context.fmtCmd(tag, formatInline(context,cap.groups[2]), attrs)
}

function inlineEmph( cap : matched, context ) : <console> string {
  val tag = if (context.starBold && cap.matched.startsWith("*")) then "strong" else "em"
  val class = tag + (if (cap.matched.startsWith("*")) then "-star" else "-low") + cap.groups[1].length.show
  val attrs = context.defaults.matchRules( tag, attrsNone.addClass(class) )
  context.fmtCmd(tag, formatInline(context,cap.groups[2]), attrs )
}

function inlineSup( cap : matched, context ) : <console> string {
  context.fmtCmd("sup", formatInline(context,cap.groups[1]), context.defaults.matchRules("sup",attrsNone))
}

function inlineSub( cap : matched, context ) : <console> string {
  context.fmtCmd("sub", formatInline(context,cap.groups[1]), context.defaults.matchRules("sub",attrsNone))
}

function inlineDel( cap : matched, context ) : <console> string {
  context.fmtCmd("del", formatInline(context,cap.groups[1]), context.defaults.matchRules("del",attrsNone))
}

function inlineTag( cap : matched, context : inlineContext ) : string {
  inlineTagX(cap.matched,context)
}

function inlineTagX( tag : string, context : inlineContext ) : string {
  if (context.sanitize || !(context.fmt.isFmtHtml))
   then "\\mdline{inlineTagX}"
   else tag
}

function inlineTagCode( cap : matched, context : inlineContext ) : <console> string {
  // TODO: we do not process fully inside <code> for now; remove this later
  // when koka documentation generates markdown instead of html.
  val icontext = context.copy(grammar = context.grammar.stripFancyRules)
  inlineTagX(cap.groups[1],context) +
   icontext.formatInline(cap.groups[2]) +
   inlineTagX(cap.groups[3],context)
}

function inlineCode( cap : matched, context ) : <console> string {
  val txt0 = cap.groups[2]
  val txt1 = if (txt0.startsWith(" `")) then txt0.substr(1) else txt0
  val txt  = if (txt0.endsWith("` ")) then txt1.substr(0,txt1.length-1) else txt1
  val attrs = if (cap.groups.matchedOn(3))
               then cap.groups[3].parseAttrs("code") else attrsNone
  if (context.bench)
   then context.fmtCode( "",txt,attrs)
   else context.fmtSpan( txt,  // can be overridden by the user
          attrs.addClasses(["code","code" + cap.groups[1].length.show]))
}

public function fmtCode( context : inlineContext, env0 : string, txt : string, attrs0 : attrs = attrsNone ) : <console> string {
  val env = if (env0=="") then "code" else env0
  trace("code: " + env + ": " + attrs0.show)
  val lang   = attrs0.hasKey("language").maybe("",id)
  val attrs1 = if (lang=="") then attrs0 else attrs0.addClasses(["language-" + lang, "lang-"+lang, lang])
  val attrs  = context.formatDefaults(attrs1,env)
  trace("code: " + env + ": " + attrs1.show)

  val cattrs = match(attrs.hasKey("data-line-first")) {
                 Nothing -> attrsNone
                 Just(v) -> attrsNone.addKeyval("data-line",v)
                }
  val cattrsTable  = if (attrs.hasBoolKey("pretty-breakable"))
                 then cattrs.addKeyvals([("pretty-breakable","true"),("tex-longtable",attrs.lookupKey("tex-longtable","longtable"))])
                 else cattrs

  val pretty = attrs.hasClass("pretty")
  val plain0 = (lang=="" || !(context.highlight) || attrs.hasClass("plain") || attrs.hasClass("prettyprint"))
  val plain = if (plain0) then plain0 else {
    if (canHilite(lang)) then False else {
      warning("unknown language: " + lang)
      True
    }
  }


  function colorize( code : string, mode : maybe<hilitemode> ) : (string,maybe<hilitemode>) {
    if (plain)
     then (code, mode)
     else match(code.hilitePartial(lang,mode)) {
            Nothing         -> (code,mode)
            Just((hl,next)) -> (hl,Just(next))
          }
  }

  function colorToken( classes : list<string>, content : string ) : <console> string {
    if (plain || classes.isNil) then content else {
      val pclasses = if (!pretty) then classes else Cons("ptoken",classes.filter(fun(cname) { cname!="token" } ))
      val tokAttrs = context.formatDefaults( attrsNone(elem="span").addClasses(pclasses) )
      context.fmtCodeToken(pclasses,content,lang,tokAttrs)
    }
  }

  function colorCode( content : string, startline : bool ) : <console> string {
    content.replaceAll("<br>","\n").replaceAll(rxEndSpaces," ").replaceAll( rxTokens, fun(cap) {
      val nl = (pretty && ((cap.index==0 && startline) || (content.substr(cap.index-1,1) == "\n")))
      if (cap.groups[2].bool) {  // token span
        val classes = cap.groups[2].split(" ").list
        colorToken( classes, context.fmtCodePlain( cap.groups[3].htmlUnescape, nl ) )
      }
      elif (cap.groups[4].bool) { // unknown tag
        ""
      }
      else { // literal
        context.fmtCodePlain( cap.matched.htmlUnescape, nl )
      }
    });
  }

  function codeEscape( code : string ) : <console> string {
    context.fmtCodeEscaped(txt,colorize,colorToken,attrs).fst   // possibly tokenize with colors, and process escapes
  }

  function codeUnescape( ecode : string, col : int ) : <console> string {
    fmtCodeUnescape( ecode, fun(s,startLine) {
      if (plain) then context.fmtCodePlain(s) else colorCode(s, startLine /* col==0 */)
    })
  }


  val pattrs0 = if (plain) then attrs else attrs.addClass("colorized")
  val pattrs = context.formatDefaults(pattrs0)
  val content
    = if (pretty && env != "code" ) then {
        val ct = codeAlign(codeEscape(txt), context.prettyAlign).map(fun(ecode, col) { codeUnescape(ecode, col) })
        context.fmtCodeTable(ct,cattrsTable)
      }
      else codeUnescape(codeEscape(txt), 0) // todo: optimize the escape/unescape path?


  if (env=="code")
   then context.fmtCmd("code", content, pattrs.mergeDefault(cattrs))
   else context.fmtEnv(env, context.fmtCmd("precode", content, cattrs), pattrs)
}

val rxEndSpaces = regex(@"  +$",multiline=True)
val rxTokens = regex( @"([^<>]+)|" + rxToken + "|(<([^>]*)>)|(.)", ignoreCase=True)
val rxToken  = @"(?:<span\s+.*?\bclass=['""]?([^""']+)['""]?[^>]*>([\s\S]*?)</span>)"

function htmlUnescape( s : string ) : string {
  s.replaceAll( rxEntity, fun(cap) {
    match(entityToNum(cap.groups[1])) {
      Nothing -> cap.matched;
      Just(i) -> string(1,i.char)
    }
  })
}
val rxEntity = regex( @"&(#[xX]\d+|\w+);" )

function fmtCodeUnescape( txt : string, fmt : (string,bool) -> <console> string ) : <console> string {
  function unspan(caps : list<matched>, i : int ) {
    match(caps) {
      Nil -> txt.substr(i).fmt(i==0)
      Cons(cap,rest) -> {
        txt.substr(i,cap.index - i).fmt(i==0) + cap.groups[1] + unspan(rest, cap.next)
      }
    }
  }
  val caps = txt.findAll(rxEscaped).list
  unspan(caps,0)
}
val rxEscaped = regex(@"<ESCAPED\b[^>]*>([\s\S]*?)</ESCAPED>")

function fmtCodeEscaped( context : inlineContext, txt : string, format : (string,maybe<a>) -> (string,maybe<a>),
                         formatToken : (list<string>,string) -> <console> string,
                         attrs : attrs = attrsNone, st : maybe<a> = Nothing ) : <console> (string,maybe<a>) {
  if (attrs.hasClass("noescape")) return format(txt,st)

  function codeEscape( src : string, st0 : maybe<_a> ) : <console> (string,maybe<_a>) {
    match( src.find(rxCodeEscaped)) {
      Nothing   -> format(src,st0)
      Just(cap) -> {
        val (fmt1,st1) = format(src.substr(0,cap.index),st0)
        val subcode    = cap.groups[2].replaceAll(regex(@"\\([^\w])"), "$1")
        val width      = if (cap.groups.matchedOn(1)) then cap.groups[1].parseInt.maybe(1,id)
                         elif (cap.groups.matchedOn(2)) then subcode.length
                         else 1
        val (fmt2,st2) = format(subcode,st1) // for colorization, use the provided substitution
        val classes2   = match(fmt2.find(rxClass)) {
                           Just(ccap) -> (ccap.groups[1] + ccap.groups[2] + ccap.groups[3]).split(" ").list
                           Nothing    -> []
                         }

        val innerEsc   = context.fmtCmd("span", context.formatInline(cap.groups[3]),
                           context.formatDefaults(attrsNone.addClass( "code-escaped" )))
        val escaped    = formatToken(classes2,innerEsc).replaceAll("%mdk-356\n","{}")
        val fmt3       = "<ESCAPED width=" + width.show + ">" + escaped + "</ESCAPED>"

        val (fmt4,st3) = codeEscape(src.substr1(cap.next),st2)
        (fmt1 + fmt3 + fmt4, st3)
      }
    }
  }

  codeEscape(txt,st)
}
//val rxCodeEscaped = regex(@"\\\((?:(\d+):)?((?:[^\\\r\n]|\\\n|\\[^\)])*)\\\)")
val rxCodeEscaped = regex(@"\\\((?:(\d+):)?(?:((?:[^\\\|]|\\[^\)])*)\|)?((?:[^\\\r\n]|\\\n|\\[^\)])*)\\\)")
val rxClass       = regex(@"^<span\s+class=(?:""([^""]*)""|'([^']*)'|([^\s\&<>]+))\s*>",ignoreCase=True)

function escapeTexPre( txt : string ) : string {
  txt.replaceAll(regex(@"\$"),@"$\text{\tt\textdollar}$")
     .replaceAll(regex(@"\|"),@"$\text{\tt\textbar}$")
}

function inlineDashes( cap : matched, context ) : <console> string {
  context.formatInline(if (cap.groups[1] != "") then "&mdash;" else "&ndash;")
}


function inlineQuotes( cap : matched, context : inlineContext ) : <console> string {
  val quote = cap.matched.substr(0,1)
  if (quote == "'")
   then context.formatInline("&lsquo;" + cap.groups[1] + "&rsquo;")
  elif (quote=="<")
   then context.formatInline("&laquo;" + cap.groups[1] + "&raquo;")
   else context.formatInline("&ldquo;" + cap.groups[2] + "&rdquo;")
}

function inlineDots( cap : matched, context ) : <console> string {
  context.formatInline("&hellip;")
}

function inlineOther( cap : matched, context ) : string {
  trace("other: " + cap.matched)
  context.fmtEscape(cap.matched)
}

function inlineEscape( cap : matched, context : inlineContext ) : <console> string {
  val txt = cap.groups[1]
  if (txt==" ") then context.formatInline("&nbsp;")
  elif (txt=="\n") then inlineBreak(cap,context)
  elif (txt=="/") then ""
  elif (context.sanitize) then context.fmtEscape(txt)
  else context.fmtText(txt)
}

function hypenateUrl( url : string ) : string {
  url.replaceAll(rxPostHyphen,"$1&#8203;").replaceAll("%","&#8203;%")
}
val rxPostHyphen = regex(@"([\-\._/\?#\[\]@!$&'\(\)\*\+,;=]+)")


function inlineAutoLink( cap : matched, context : inlineContext ) : <console> string {
  val attrs  = if (cap.groups.matchedOn(3)) then context.formatAttrs(cap.groups[3].parseAttrs) else attrsNone
  val attrsd = context.defaults.matchRules( "a", attrs.addClass("texturl"))
  if (cap.groups[2] == "@") {
    val text = cap.groups[1].replace(regex(@"^mailto:"),"")
    val url  = "mailto:" + text
    context.fmtLink(False,newLink(url,linkattrs=attrsd,bench=context.bench),context.fmtEscape(text.hypenateUrl))
  }
  else {
    context.fmtLink(False,newLink(cap.groups[1],linkattrs=attrsd,bench=context.bench),context.fmtEscape(cap.groups[1].hypenateUrl))
  }
}

function inlineLink( cap : matched, context : inlineContext ) : <console> string {
  inlineLinkEx(False,cap,context)
}

function inlineImg( cap : matched, context : inlineContext ) : <console> string {
  inlineLinkEx(True,cap,context)
}

function inlineLinkEx( isImage : bool, cap : matched, context : inlineContext ) : <console> string {
  // cap.groups = 1:optional spaces, 2:txt, 3:everything after it,
  //               AND 4:href, 5:href-title, OR 6: linkid, AND 7:span attributes
  val attrs  = if (cap.groups.matchedOn(7)) then context.formatAttrs(cap.groups[7].parseAttrs) else attrsNone
  //val attrs   = context.applyDefaults(if (isImage) then "img" else "a", attrs0)

  val nbsp = if (cap.groups[1] != "" && cap.groups[1].list.all(fun(c){c==' '}))
              then context.fmtText("&nbsp;") else cap.groups[1]
  if (cap.groups.matchedOn(4)) {
    // direct url link:  [text](url title){attrs}
    val attrsd = context.defaults.matchRules( if (isImage) then "img" else "a", attrs)
    nbsp + context.fmtLink(isImage, newLink(cap.groups[4],cap.groups[5],attrsd,bench=context.bench),
                                 context.formatInline(cap.groups[2]))
  }
  elif (context.bench || cap.groups.matchedOn(6)) {
    // [text][ref]{attrs}
    inlineLinkRef(isImage, cap.groups[1], nbsp, cap.groups[2], cap.groups[3], cap.groups[6], attrs, context )
  }
  else {
    // [text]{attrs}
    inlineLinkNoRef(isImage, cap.groups[1], nbsp, cap.groups[2], cap.groups[3], attrs, context)
  }
}

struct cite(
  name    : string,
  pre     : string,
  post    : string,
  modifier: string,
  number  : string,
  year    : string,
  authors : string,
  ordinal : int
)

function inlineLinkNoRef( isImage:bool, spaces : string, nbsp : string, txt : string, after : string, attrs : attrs, context : inlineContext ) : <console> string
{
  // TODO do not look up citation in context.labels[lab] (since we don't use BIB)!
  val citationss
            = if (context.bench || !(txt.contains("@"))) then Nil
                else txt.splitExclude(rxCiteSep,rxCiteSepExclude).map(fun(elem) {
                        match (elem.find(rxCitation)) {
                          Nothing -> []
                          Just(cap) -> {
                            log("aux",@"\citation{" + cap.groups[3] + "}")
                            val lab = ("@" + cap.groups[3])
                            [Cite(lab.substr(1), cap.groups[1], cap.groups[4], cap.groups[2], "NUMBER", "YEAR", "AUTHORS", 0)]
                          }
                        }
                      })

  // trace("citations: " + citationss.concat.join("-"))
  if (citationss.isCons && citationss.all(isCons)) {
    // Citations link: set defaults as "citations" block
    val attrsc = attrs.addKeyval("target-element","bibitem")
    val attrsd = context.defaults.matchRules("citations",attrsc)
    context.fmtCite(nbsp,citationss.concat,attrsd)
  }
  else {
    inlineLinkRef( isImage, spaces, nbsp, txt, after, "", attrs, context )
  }
}
val rxCiteSep         = regex(@"\s*[;]\s*")
val rxCiteSepExclude  = regex(@"[^\\;\s]|\\.")
val rxCitation        = regex(@"^((?:[^\w\\@+!-]|[+!-](?!@)|\\.|\w(?![+!-]?@))*)(?:([+!-]?)@" + rxCitename + @")([\s\S]*)$")
val rxCitename        = @"(\w(?:[\w]|[:\-\.]\w)*)"

function inlineCite( cap : matched, context : inlineContext ) : <console> string {
  log("aux",@"\citation{" + cap.groups[4] + "}")
  context.formatInline(cap.groups[1] + "[" + cap.groups[2] + "]{.textual" +
    (if (cap.groups[3]=="-") then " .free" else "") + "}")
}

function inlineLinkRef( isImage : bool, spaces : string, nbsp : string, txt : string, after : string, ref : string,
                          attrs : attrs, context : inlineContext ) : <console> string
{
  val id = if (ref != "") then ref.definitionId else txt.definitionId
  val elemName = if (isImage) then "img" else "a"
  match(context.links[id]) {
    Just(link) -> {
      val attrsd = context.defaults.matchRules(elemName,attrs)
      val xlink = if (attrsd.empty) then link else link( linkattrs = attrsd.mergeDefault(link.linkattrs) )
      nbsp + context.fmtLink(isImage, xlink, context.formatInline(txt))
    }
    Nothing -> {
      // Link not found! Try if it is a label
      val labelId = if (id.startsWith("#")) then id.substr(1) else ""
      match(context.labels[labelId]) {
        Just(lab) -> {
          // Label reference
          val attrsd = context.defaults.matchRules(elemName,attrs)
          val lattrs = attrsd.addKeyval("target-element",lab.element)
          val llink  = newLink(id,context.formatInline(lab.labelCaption),lattrs,bench=context.bench)
          nbsp + context.fmtLink(isImage,llink,context.formatInline(
                                 if (ref=="") then "&" + labelId + ";" else txt))
        }
        Nothing -> {
          if (ref != "") then {
            warning( "missing link definition: " + ref)
            spaces + context.formatInline(txt) + "[??]"
          }
          elif (!(attrs.empty)) {
            // Span element
            // TODO if we replace the mdline with a newline, this will be stripped somehow.
            // CONJECTURE: trim is invoked in the result, removing the newline, but keeping the %...
            // BUT WHY?
            //
            // Also alternatively removing %mdk-565 doesn't help since then there might be
            // to many newlines (for instance in effekt-standalone/Theorem4.4).
            spaces + context.fmtSpan(txt,attrs) + "\\mdline{inlineLinkRef}"
          }
          else {
            // warn for missing labels or links
            if (txt.contains(rxCanBeRef)) {
              if (txt.startsWith("#")) {
                warning( "reference to missing id: " + txt)
              }
              elif (context.labels[id].isJust) {
                warning( "possibly forgot '#' to reference id: " + txt)
              }
              else {
                warning( "possibly missing link definition or id: " + txt)
              }
            }

            // just brackets
            spaces + "[" + formatInline(context,txt) + "]" + formatInline(context,after)
          }
        }
      }
    }
  }
}

val rxCanBeRef = regex(@"^#?[A-Za-z_][\w-]*$")

// get and format default attributes
function formatDefaults( context : inlineContext, attrs : attrs, elemName : string = "" ) : <console> attrs {
  if (!(attrs.defaults)) return attrs

  val sname = if (elemName != "") then elemName
              elif (attrs.elem != "") then attrs.elem
              else match (attrs.classes) {
                Cons(cname,_) -> cname
                _             -> "span"
              } //attrs.elementName("span")
  val attrsx  = context.defaults.matchRules(sname,attrs)
  context.formatAttrs(attrsx)
}

// Format a span element
function fmtSpan( context : inlineContext, txt0 : string, attrs : attrs ) : <console> string {
  val sname   = if (attrs.elem != "") then attrs.elem
                else match (attrs.classes) {
                  Cons(cname,_) -> cname
                  _             -> "span"
                } //attrs.elementName("span")
  val attrsx  = context.defaults.matchRules(sname,attrs)
  val attrsd  = context.formatAttrs(attrsx)

  // this runs the replacers
  val txt = attrsd.transformText(txt0,context.labels,context.metadata)
  match(attrsd.input) {
    Pre      -> context.fmtCode("", txt, attrsd) // todo: use sname as env name?
    Math     -> context.fmtMath(False,txt.mathUnline,attrsd)
    MathPre  -> context.fmtMath(False,txt.mathUnline.mathPre,attrsd)
    Raw(monly) -> {
      if (context.sanitize) then ""
       else match(monly) {
        Nothing -> context.fmtCmd("span", txt, attrsd )
        Just(f) | f == context.fmt -> context.fmtCmd("span", txt, attrsd )
        _       -> ""
       }
    }
    Markdown(Just(f)) | !(f == context.fmt) -> ""
    Markdown | attrsd.notag -> context.formatInline(txt)
    // MathDefs, Tex, Markdown
    _  -> context.fmtCmd("span", context.formatInline(txt), attrsd )
  }
}

public function fmtPoly( context : inlineContext, txt0 : string, attrs : attrs = attrsNone) : <console> string {
  // add newline because of comments in latex (and we do use trimLines on the content)
  val (kind,left,right,rightx) = ("Display","\\[" + (if (attrs.name.isEmpty) then "" else "\\label{" + attrs.name + "}"),"\n\\]","%mdk-614\n")

  // idea: have special math mode where we
  // 1) compute the alignment
  // 2) generate polytable code and insert linebreaks etc.
  // 3) then run the replacements on the generated code

  // do some alignment computations:
  val aligned = codeAlign(txt0)
  trace(aligned.show)

  // generate layout
  val txt1 = fmtLatexPolyTable(context, aligned, attrs)

  // perform replacements
  val txt = attrs.transformText(txt1, context.labels, context.metadata)

  val lkind  = kind.toLower
  val class  = "math-" + lkind
  val attrsd = context.applyDefaults("span",attrs.addClass(class))

  if (kind=="Inline")
    then context.fmtMathCmd("span", left+txt+right+rightx, attrsd)
    else context.fmtMathEnv("div",  left+txt+right+rightx, attrsd)
}

function mathUnline( txt : string ) {
  txt.replaceAll(rxCont,"$1")  // allow line breaks in inline-math
}
val rxCont = regex(@"(\\%)|(?:%.*)?\n[ \t]*")

// Format a citation link
function fmtCite(context : inlineContext, nbsp: string, citations : list<cite>, attrs : attrs ) : string
{
  val isTextual = (attrs.hasClass("textual"))

  function year(cite: cite) { cite.modifier.contains("-") }
  function authors(cite: cite) { cite.modifier.contains("!") }
  function allauthors(cite: cite) { cite.modifier.contains("+") }

  // @Goo93	 Goossens et al. (1993)	Textual style
  // +@Goo93	 Goossens, Mittelbach, and Samarin (1993)	Long – all authors
  // -@Goo93	 1993	Short – just year
  // !@Goo93	 Goossens et al.	Just authors
  if (isTextual) {
    val res = match(citations) {
      Cons(cite, _) -> {
        if (cite.year) {
          "\\citeyear{" + cite.name + "}"
        } elif (cite.authors) {
          "\\citeauthor{" + cite.name + "}"
        } elif (cite.allauthors) {
          "\\citet*{" + cite.name + "}"
        } else {
          "\\citet{" + cite.name + "}"
        }
      }
      Nil -> {
        warning( "Should not happen")
        ""
      }
    }
    nbsp + res

  // [@Goo93]	 (Goossens et al., 1993)	Natural
  // [+@Goo93]	 (Goossens, Mittelbach, and Samarin, 1993)	Long – all authors
  // [-@Goo93]	 (1993)	Short – just year
  } else {
    val cites = citations.map(fun(cite){ cite.name }).join(", ")
    // TODO also support other cite styles
    nbsp + "\\citep{" + cites + "}"
  }
}

// Format attributes
function formatAttrs( context : inlineContext, attrs : attrs ) : <console> attrs {
  attrs( label = context.formatInline(attrs.label) ).expand(context.metadata )
}

// Apply defaults
function applyDefaults( context : inlineContext, sname : string, attrs : attrs ) : <console> attrs {
  context.defaults.matchRules(sname,attrs)
}

function inlineFootnote( cap : matched, context : inlineContext ) : <console> string {
  val id = cap.groups[1].definitionId
  match( context.footnotes[id] ) {
    Just(fn:footnote) -> context.fmtFootnote(id,fn(footnoteNum = context.formatInline(fn.footnoteNum),
                                                   footnoteCaption = context.formatInline(fn.footnoteCaption)))
    Nothing -> {
      warning( "missing footnote definition: " + cap.groups[1])
      context.fmtText("[^" + formatInline(context,cap.groups[1]) + "]") // leave as plain text?
    }
  }
}

function isort( xs : list<a>, gt : (a,a) -> bool ) : list<a> {
  match(xs) {
    Cons(x,xx) -> insert(x,xx.isort(gt),gt)
    Nil -> Nil
  }
}

function insert( x : a, xs : list<a>, gt : (a,a) -> bool ) : list<a> {
  match(xs) {
    Cons(y,yy) -> if (gt(x,y)) then Cons(y,insert(x,yy,gt)) else Cons(x,xs)
    Nil -> [x]
  }
}
