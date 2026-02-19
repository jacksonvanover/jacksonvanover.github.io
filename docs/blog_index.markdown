---
layout: default
title: Technical Blog
permalink: /blog/
---

<h1>Jackson's Technical Blog</h1>

{% for post in site.posts %}
  {% if post.pinned %}
<p style="margin: 0; padding: 0">
    📌 <a href="{{ post.url }}" style="text-decoration: underline; font-size: 20px;">
    {{ post.title }}
    </a>
</p>
<p style="margin: 0 0 0 20px; padding: 0">
    <b>{{ post.date | date: "[%m/%d/%y]" }}</b>
</p>
<p style="font-style: italic; margin-left: 50px;">
    DISCUSSED: {{ post.discussed }}
</p>
<hr style="border: none; height: 2px; background-color: #267cb9;">
  {% endif %}
{% endfor %}

{% for post in site.posts %}
{% unless post.pinned %}
<p style="margin: 0; padding: 0">
    <a href="{{ post.url }}" style="text-decoration: underline; font-size: 20px;">
    {{ post.title }}
    </a>
</p>
<p style="margin: 0 0 0 20px; padding: 0">
    <b>{{ post.date | date: "[%m/%d/%y]" }}</b>
</p>
<p style="font-style: italic; margin-left: 50px;">
    DISCUSSED: {{ post.discussed }}
</p>
{% endunless %}
{% endfor %}
