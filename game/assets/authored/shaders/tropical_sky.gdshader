shader_type sky;
// Original static tropical late-afternoon sky. No photographed skyline/backdrop.
// Matched to the approved concepts: warm gold horizon, deeper blue zenith,
// cloud undersides lit from a low sun.
uniform vec3 zenith : source_color = vec3(0.15, 0.33, 0.58);
uniform vec3 horizon : source_color = vec3(0.96, 0.80, 0.62);
uniform vec3 ground_haze : source_color = vec3(0.62, 0.60, 0.55);
uniform vec3 sun_direction = vec3(0.85, 0.28, 0.45);
float hash3(vec3 p) { return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453); }
float noise3(vec3 p) {
 vec3 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(mix(hash3(i),hash3(i+vec3(1,0,0)),f.x),mix(hash3(i+vec3(0,1,0)),hash3(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash3(i+vec3(0,0,1)),hash3(i+vec3(1,0,1)),f.x),mix(hash3(i+vec3(0,1,1)),hash3(i+vec3(1,1,1)),f.x),f.y),f.z);
}
float fbm(vec3 p) {
 float n=0.0; float a=0.55;
 for(int i=0;i<5;i++){n+=noise3(p)*a;p=p*2.03+vec3(3.1,2.7,1.9);a*=0.48;}
 return n;
}
void sky() {
 vec3 ray=normalize(EYEDIR);
 float h=max(ray.y,0.0);
 // Warm band hugging the horizon, cooler and deeper overhead.
 vec3 col=mix(horizon,zenith,pow(h,0.42));
 vec3 sd=normalize(sun_direction);
 float facing=max(dot(ray,sd),0.0);
 // Broad forward-scatter halo plus the tighter disc below.
 col+=vec3(1.0,0.55,0.20)*pow(facing,6.0)*0.30;
 col+=vec3(1.0,0.72,0.38)*pow(facing,26.0)*0.55;
 if(ray.y>0.010){
  // Clouds live on a flat deck, so sample a planar projection rather than the
  // ray direction. Sampling EYEDIR directly produced vertical streaks near the
  // horizon in the first wave-3 pass.
  float deck=max(ray.y,0.055);
  vec2 uv=ray.xz/deck;
  vec3 p=vec3(uv.x,uv.y,0.0)*0.32+vec3(11.3,4.7,0.0);
  float cloud=fbm(p);
  float cover=smoothstep(.50,.70,cloud)*smoothstep(.02,.16,h);
  float edge=fbm(p+vec3(sd.x,sd.z,0.0)*0.35);
  // Undersides pick up the warm sun; tops stay cool grey-blue.
  vec3 shade=mix(vec3(.42,.47,.55),vec3(1.0,.84,.63),clamp(.50+(edge-cloud)*4.2,0.0,1.0));
  col=mix(col,shade,cover*.92);
 }
 float disk=smoothstep(.99993,.99997,facing);
 col+=vec3(1.0,.78,.46)*disk*7.0;
 if(ray.y<0.0) col=mix(ground_haze,vec3(.16,.15,.13),smoothstep(0.0,.3,-ray.y));
 COLOR=col;
}
