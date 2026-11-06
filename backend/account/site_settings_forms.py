from django import forms
from .models import SiteSettings


class SiteSettingsForm(forms.ModelForm):
    class Meta:
        model = SiteSettings
        fields = "__all__"
        widgets = {"xmax_api_key": forms.PasswordInput(render_value=True, attrs={"autocomplete": "new-password"})}

    # def __init__(self, *args, **kwargs):
    #     super().__init__(*args, **kwargs)
    #     # Realtime-only installations do not need a legacy Decart key.
    #     self.fields["decart_api_key"].required = False

    def clean_xmax_api_key(self):
        return self.cleaned_data.get("xmax_api_key", "").strip()


