---
layout: default
title: Technical Blog
permalink: /blog/
---

# Jackson's Technical Blog
{% for post in site.posts %}
<p style="margin: 0px; padding: 0px">
<a href="{{ post.url }}" style="text-decoration: underline; font-size: 20px;">{{ post.title }}</a>
</p>
<p style="margin: 0px; margin-left: 20px; padding: 0px">
<b>{{post.date | date: "[%m/%d/%y]"}}</b>
</p>
<p style="font-style: italic; margin-left: 50px;">
DISCUSSED: {{post.discussed}}
</p>
{% endfor %}