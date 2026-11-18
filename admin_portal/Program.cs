using AdminPortal.Services;
using Microsoft.AspNetCore.Authentication.Cookies;

var builder = WebApplication.CreateBuilder(args);

// Supabase settings (Url from appsettings.json, AnonKey from user-secrets)
builder.Services.Configure<SupabaseOptions>(builder.Configuration.GetSection("Supabase"));
builder.Services.AddHttpContextAccessor();
builder.Services.AddHttpClient<SupabaseClient>();

// Cookie login. The Supabase access/refresh tokens are stored as claims in the
// encrypted auth cookie, so every request can call Supabase as the signed-in admin
// and Row Level Security applies (NFR-004).
builder.Services
    .AddAuthentication(CookieAuthenticationDefaults.AuthenticationScheme)
    .AddCookie(o =>
    {
        o.LoginPath = "/Account/Login";
        o.AccessDeniedPath = "/Account/Login";
        o.ExpireTimeSpan = TimeSpan.FromHours(8);
        o.SlidingExpiration = true;
        o.Cookie.HttpOnly = true;
        o.Cookie.SecurePolicy = CookieSecurePolicy.Always;
    });

builder.Services.AddAuthorization(o =>
{
    // Use case diagram: "Authenticate User <<include>> Role based access control"
    o.AddPolicy("Admin", p => p.RequireRole("admin"));
    o.AddPolicy("Cafeteria", p => p.RequireRole("cafeteria"));
    o.AddPolicy("AdminOrCafeteria", p => p.RequireRole("admin", "cafeteria"));
});

builder.Services.AddControllersWithViews();

var app = builder.Build();

if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Dashboard/Error");
    app.UseHsts();
}

app.UseHttpsRedirection();
app.UseStaticFiles();
app.UseRouting();
app.UseAuthentication();
app.UseAuthorization();

app.MapControllerRoute(name: "default", pattern: "{controller=Dashboard}/{action=Index}/{id?}");

app.Run();
