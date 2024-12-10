#!/bin/sh

#run: SITE_DOMAIN="$( git rev-parse --show-toplevel )/public" sh -c './% "${SITE_DOMAIN}" "en" "/"'

domain="${1}"
lang="${2}"
curr_path="${3}"

highlight_curr() {
  link="${1}"
  name="${2}"
  path="${3}"

  if [ "${curr_path}" != "${curr_path#"${path}"}" ]; then
    printf '<span class="current"><a href="%s">%s</a></span>' "${domain}/${path}" "${name}"
  else
    printf '<span><a href="%s">%s</a></span>' "${domain}/${path}" "${name}"
  fi
}
s='    '


<<EOF cat -
${s}<nav id="top" class="link-hover-only-underline"><!--
${s}  --><span class="sitelogo"><a href="${domain}/${lang}/">Home</a></span><!--
${s}  -->$( highlight_curr "projects.html" "Projects" "${lang}/projects.html" )<!--
${s}  -->$( highlight_curr "notes.html"    "Notes"    "${lang}/notes.html" )<!--
${s}  -->$( highlight_curr "blog.html"     "Blog"     "${lang}/blog" )<!--
${s}  -->$( highlight_curr "about.html"    "About"    "${lang}/about.html" )<!--
${s}--></nav>
EOF
