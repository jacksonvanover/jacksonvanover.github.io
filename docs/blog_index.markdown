---
layout: default
title: Technical Blog
permalink: /blog/
---

# Jackson's Technical Blog
<ul>
  {% for post in site.posts %}
      <a href="{{ post.url }}" style="text-decoration: underline; font-size: 20px;">{{ post.title }}</a>
      <br>
      <b>{{post.date | date: "[%m/%d/%y]"}}</b>
      <p style="font-style: italic; margin-left: 40px;">
      DISCUSSED: {{post.discussed}}
      </p>
  {% endfor %}
</ul>