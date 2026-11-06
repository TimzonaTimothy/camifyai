from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [("account", "0013_auto_20260622_1101")]

    operations = [
        migrations.AddField(
            model_name="sitesettings",
            name="xmax_api_key",
            field=models.CharField(
                max_length=300,
                blank=True,
                default="",
                verbose_name="XMax API Key",
                help_text="Permanent key for realtime streaming. Changes apply to new and reconnected sessions.",
            ),
        ),
    ]
