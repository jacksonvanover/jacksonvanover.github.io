---
layout: default
title: Technical Blog
permalink: /blog/
---

# Jackson's Technical Blog
<ul>
  {% for post in site.posts %}
      <a href="{{ post.url }}" style="text-decoration: underline; font-size: 20px;">{{ post.title }}</a>
      <p style="margin: 0px; margin-left: 20px; padding: 0px">
      <b>{{post.date | date: "[%m/%d/%y]"}}</b>
      </p>
      <p style="font-style: italic; margin-left: 50px;">
      DISCUSSED: {{post.discussed}}
      </p>
  {% endfor %}
</ul>